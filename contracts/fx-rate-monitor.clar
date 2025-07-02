;; FX Rate Monitoring System
;; Tracks and manages foreign exchange rates

;; Data structures
(define-map current-rates
  { currency-pair: (string-ascii 10) }
  {
    rate: uint,
    last-updated: uint,
    volatility: uint,
    daily-high: uint,
    daily-low: uint
  }
)

(define-map rate-history
  { currency-pair: (string-ascii 10), timestamp: uint }
  { rate: uint, volume: uint }
)

(define-map rate-alerts
  { alert-id: (string-ascii 50) }
  {
    currency-pair: (string-ascii 10),
    threshold-type: (string-ascii 10),
    threshold-value: uint,
    specialist-id: (string-ascii 50),
    is-active: bool
  }
)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INVALID-RATE (err u400))
(define-constant ERR-PAIR-NOT-FOUND (err u404))
(define-constant ERR-ALERT-EXISTS (err u409))

;; Authorization
(define-constant CONTRACT-OWNER tx-sender)

;; Update FX rate
(define-public (update-fx-rate
  (currency-pair (string-ascii 10))
  (new-rate uint)
  (volume uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-rate u0) ERR-INVALID-RATE)

    (let ((current-data (default-to
            {rate: new-rate, last-updated: u0, volatility: u0, daily-high: new-rate, daily-low: new-rate}
            (map-get? current-rates {currency-pair: currency-pair}))))

      ;; Update current rate
      (map-set current-rates
        {currency-pair: currency-pair}
        {
          rate: new-rate,
          last-updated: block-height,
          volatility: (calculate-volatility (get rate current-data) new-rate),
          daily-high: (if (> new-rate (get daily-high current-data)) new-rate (get daily-high current-data)),
          daily-low: (if (< new-rate (get daily-low current-data)) new-rate (get daily-low current-data))
        })

      ;; Store historical data
      (map-set rate-history
        {currency-pair: currency-pair, timestamp: block-height}
        {rate: new-rate, volume: volume})

      (ok true))))

;; Calculate rate volatility
(define-private (calculate-volatility (old-rate uint) (new-rate uint))
  (if (>= new-rate old-rate)
    (/ (* (- new-rate old-rate) u100) old-rate)
    (/ (* (- old-rate new-rate) u100) old-rate)))

;; Get current exchange rate
(define-read-only (get-current-rate (currency-pair (string-ascii 10)))
  (map-get? current-rates {currency-pair: currency-pair}))

;; Get rate history
(define-read-only (get-rate-history (currency-pair (string-ascii 10)) (timestamp uint))
  (map-get? rate-history {currency-pair: currency-pair, timestamp: timestamp}))

;; Calculate rate volatility over period
(define-read-only (calculate-rate-volatility
  (currency-pair (string-ascii 10))
  (start-time uint)
  (end-time uint))
  (let ((current-rate-data (unwrap! (map-get? current-rates {currency-pair: currency-pair}) ERR-PAIR-NOT-FOUND)))
    (ok (get volatility current-rate-data))))

;; Set up rate alert
(define-public (setup-rate-alert
  (alert-id (string-ascii 50))
  (currency-pair (string-ascii 10))
  (threshold-type (string-ascii 10))
  (threshold-value uint)
  (specialist-id (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? rate-alerts {alert-id: alert-id})) ERR-ALERT-EXISTS)

    (map-set rate-alerts
      {alert-id: alert-id}
      {
        currency-pair: currency-pair,
        threshold-type: threshold-type,
        threshold-value: threshold-value,
        specialist-id: specialist-id,
        is-active: true
      })
    (ok alert-id)))

;; Check rate alerts
(define-read-only (check-rate-alerts (currency-pair (string-ascii 10)))
  (let ((rate-data (unwrap! (map-get? current-rates {currency-pair: currency-pair}) ERR-PAIR-NOT-FOUND)))
    (ok (get rate rate-data))))
