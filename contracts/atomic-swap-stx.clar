;; ------------------------------------------------------------
;; AtomicSwapSTX - HTLC-s          (map-set swaps { id: id } (merge swap { status: STATUS_CLAIMED, preimage: (some (to-consensus-buff? preimage)) }))yle Atomic Swap (Stacks / Clarity v3)
;; ------------------------------------------------------------
;; Purpose:
;; - Implements the STX-side of an atomic swap (hashlock + timelock).
;; - Initiator locks STX for a recipient, providing a hashlock (sha256) and timelock (block height).
;; - Recipient claims the STX by presenting the preimage whose sha256 == hashlock.
;; - If recipient does not claim before timelock, initiator can refund the STX.
;; ------------------------------------------------------------

(define-constant ERR-BAD-ARGS     (err u100))
(define-constant ERR-NOT-FOUND    (err u101))
(define-constant ERR-UNAUTHORIZED (err u102))
(define-constant ERR-ALREADY      (err u103))
(define-constant ERR-TOO-EARLY    (err u104))
(define-constant ERR-TOO-LATE     (err u105))
(define-constant ERR-INSUFFICIENT (err u106))

;; Swap status codes
(define-constant STATUS_OPEN   u0)
(define-constant STATUS_CLAIMED u1)
(define-constant STATUS_REFUNDED u2)

;; Incremental swap id
(define-data-var next-swap-id uint u1)

;; Each swap record
(define-map swaps
  { id: uint }
  {
    initiator: principal,    ;; who locked the STX (refunds allowed to this principal)
    recipient: principal,    ;; intended recipient who can claim by presenting preimage
    amount: uint,            ;; STX amount locked
    hashlock: (buff 32),     ;; SHA256(preimage)
    timelock: uint,          ;; block height after which initiator can refund
    status: uint,            ;; STATUS_OPEN / STATUS_CLAIMED / STATUS_REFUNDED
    preimage: (optional (buff 32)) ;; stores revealed preimage on claim (optional)
  })

;; ----------------- Helpers -----------------
(define-read-only (now) burn-block-height)

(define-read-only (swap-exists? (id uint))
  (is-some (map-get? swaps { id: id })))

(define-read-only (get-swap (id uint))
  (match (map-get? swaps { id: id }) value (ok value) (err ERR-NOT-FOUND)))

;; ----------------- Create swap (initiator locks STX) -----------------
;; initiator provides `recipient`, `amount` (STX), `hashlock` (buff 32), `timelock` (block height)
(define-public (create-swap (recipient principal) (hashlock (buff 32)) (timelock uint))
  (let ((amount (stx-get-balance tx-sender)))
    (begin
      ;; basic checks
      (asserts! (and (> amount u0) (is-eq (len hashlock) u32)) ERR-BAD-ARGS)
      (asserts! (> timelock (now)) ERR-BAD-ARGS)
      (asserts! (not (is-eq tx-sender recipient)) ERR-BAD-ARGS)
      (let ((id (var-get next-swap-id)))
        ;; transfer already happened to this contract by the transaction sender
        ;; create swap record
        (map-set swaps { id: id }
          {
            initiator: tx-sender,
            recipient: recipient,
            amount: amount,
            hashlock: hashlock,
            timelock: timelock,
            status: STATUS_OPEN,
            preimage: none
          })
        (var-set next-swap-id (+ id u1))
        (ok id)))))

;; ----------------- Claim (recipient presents preimage) -----------------
;; preimage must be (buff 32) such that (sha256 preimage) == stored hashlock
(define-public (claim (id uint) (preimage (buff 32)))
  (let ((swap (unwrap! (map-get? swaps { id: id }) ERR-NOT-FOUND)))
    (let ((status (get status swap))
          (hashlock (get hashlock swap))
          (recip (get recipient swap))
          (amt (get amount swap)))
      (begin
        (asserts! (and (swap-exists? id) (is-eq status STATUS_OPEN)) ERR-ALREADY)
        (asserts! (is-eq tx-sender recip) ERR-UNAUTHORIZED)
        (asserts! (is-eq (sha256 preimage) hashlock) ERR-BAD-ARGS)
        ;; transfer STX to recipient
        (asserts! (is-ok (stx-transfer? amt (as-contract tx-sender) recip)) ERR-INSUFFICIENT)
        (map-set swaps { id: id } { 
          initiator: (get initiator swap),
          recipient: recip,
          amount: amt,
          hashlock: hashlock,
          timelock: (get timelock swap),
          status: STATUS_CLAIMED,
          preimage: (some preimage)
        })
        (ok true)))))

;; ----------------- Refund (initiator after timelock) -----------------
(define-public (refund (id uint))
  (let ((swap (unwrap! (map-get? swaps { id: id }) ERR-NOT-FOUND)))
    (let ((status (get status swap))
          (initiator (get initiator swap))
          (amt (get amount swap))
          (timelock (get timelock swap)))
      (begin
        (asserts! (and (swap-exists? id) (is-eq status STATUS_OPEN)) ERR-ALREADY)
        (asserts! (is-eq tx-sender initiator) ERR-UNAUTHORIZED)
        (asserts! (>= (now) timelock) ERR-TOO-EARLY)
        (asserts! (is-ok (stx-transfer? amt (as-contract tx-sender) initiator)) ERR-INSUFFICIENT)
        (map-set swaps { id: id } {
          initiator: initiator,
          recipient: (get recipient swap),
          amount: amt,
          hashlock: (get hashlock swap),
          timelock: timelock,
          status: STATUS_REFUNDED,
          preimage: (get preimage swap)
        })
        (ok true)))))

;; ----------------- Views -----------------
(define-read-only (get-swap-info (id uint))
  (let ((swap (unwrap! (map-get? swaps { id: id }) ERR-NOT-FOUND)))
    (ok {
      id: id,
      initiator: (get initiator swap),
      recipient: (get recipient swap),
      amount: (get amount swap),
      timelock: (get timelock swap),
      status: (get status swap),
      hashlock: (get hashlock swap),
      preimage: (get preimage swap)
    })))

;; convenience view: check whether a given preimage matches the stored hashlock
(define-read-only (verify-preimage (id uint) (preimage (buff 32)))
  (let ((swap (unwrap! (map-get? swaps { id: id }) ERR-NOT-FOUND)))
    (ok (is-eq (sha256 preimage) (get hashlock swap)))))