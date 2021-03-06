#lang racket

(require "../forwardbackward.rkt" "../inst.rkt"
         "arm-inst.rkt" "arm-machine.rkt")

(provide arm-forwardbackward%)

(define arm-forwardbackward%
  (class forwardbackward%
    (super-new)
    (inherit-field machine printer)
    (override len-limit window-size
              mask-in inst->vector
              change-inst change-inst-list
	      get-live-mask try-cmp? combine-live sort-live sort-live-bw)

    (define shf-inst-imm (get-field shf-inst-imm machine))

    ;; Num of instructions that can be synthesized within a minute.
    (define (len-limit) 2)

    ;; Context-aware window decomposition size L.
    ;; The cooperative search tries L/2, L, 2L, 4L.
    (define (window-size) 4)

    (define opcodes (get-field opcodes machine))
    (define cmp-inst
      (map (lambda (x) (vector-member x opcodes))'(cmp tst cmp# tst#)))

    ;; Convert instruction into vector/list/pair format.
    (define (inst->vector x)
      (vector (inst-op x) (inst-args x) (inst-shfop x) (inst-shfarg x) (inst-cond x)))

    ;; Mask in only the live values. If an entry in progstate is not live, set it to #f.
    ;; state-vec: progstate in vector/list/pair format
    ;; live-list: liveness in compact format
    ;; keep-flag: if #f, set flag to default value.
    ;; output: masked progstate in vector/list/pair format
    (define (mask-in state-vec live-list #:keep-flag [keep #t])
      (define live-reg (car live-list))
      (define live-mem (cdr live-list))
      
      (define regs (vector-ref state-vec 0))
      (define mems (vector-ref state-vec 1))
      (define z (vector-ref state-vec 2))
      (define fp (vector-ref state-vec 3))
      (vector
       (for/vector ([r regs] [i (in-naturals)])
		   (and (member i live-reg) r))
       (for/vector ([m mems] [i (in-naturals)])
		   (and (member i live-mem) m))
       (if keep z -1) fp))

    ;; Extract liveness from programstate. If an entry is a number, then it is live.
    ;; state-vec: progstate in vector/list/pair format
    ;; output: liveness in compact format.
    (define (get-live-mask state-vec)
      (cons
       ;; registers
       (filter number?
               (for/list ([i (in-naturals)]
                          [r (vector-ref state-vec 0)])
                         (and r i)))
       ;; memory
       (filter number?
               (for/list ([i (in-naturals)]
                          [r (vector-ref state-vec 1)])
                         (and r i)))
       )
      )
    
    (define (change-inst x change)
      (define base-inst (super change-inst x change))
      (define shfop-name (and (inst-shfop x) (send machine get-shf-inst-name (inst-shfop x))))
      (define shfarg (inst-shfarg x))

      (define new-shfarg
        (if (member shfop-name shf-inst-imm)
            (change shfarg `bit)
            shfarg))

      (arm-inst (inst-op x) (inst-args base-inst)
                (inst-shfop x) new-shfarg (inst-cond x)))
    
    (define (change-inst-list x change)
      (define op (inst-op x))
      (define shfop (inst-shfop x))
      (define cond-type (inst-cond x))
      (define base-list (super change-inst-list x change))

      (define shfop-name (and (inst-shfop x) (send machine get-shf-inst-name (inst-shfop x))))
      (define shfarg (inst-shfarg x))

      (define new-shfarg
        (if (member shfop-name shf-inst-imm)
            (change shfarg `bit)
            (list shfarg)))

      (for*/list ([base-inst base-list]
                  [shfarg-final new-shfarg])
                 (arm-inst op (inst-args base-inst)
                           shfop shfarg-final cond-type)))

    ;; Analyze if we should include comparing instructions into out instruction pool.
    ;; code: input program
    ;; state: program state in progstate format
    ;; live: live-in information in progstate format
    (define (try-cmp? code state live)
      (define z (progstate-z state))
      (define live-z (progstate-z live))
      (define use-cond1 (for/or ([x code]) (member (inst-op x) cmp-inst)))
      (define use-cond2 (for/or ([x code]) (not (= (inst-cond x) 0))))

      (cond
       [(and live-z (> z -1) use-cond1) 1]
       [(and (> z -1) (or use-cond1 use-cond2)) 2]
       [else 0]))

    ;; Combine livenss information at an abitrary point p in the program.
    ;; x: liveness from executing the program from the beginning to point p.
    ;; y: liveness from analyzing the program backward from the end to point p.
    (define (combine-live x y) 
      ;; Use register's liveness from x but memory's liveness from y.
      (cons (car x) (cdr y)))

    ;; Sort liveness. Say we have program prefixes that have different live-outs.
    ;; If liveness A comes before B, program prefix with live-out A will be considered before program prefix with live-out B.
    (define (sort-live keys)
      (sort keys (lambda (x y) (> (length (car (entry-live x))) (length (car (entry-live y)))))))

    ;; Similar to 'sort-live' but for backward direction (program postfixes).
    (define (sort-live-bw keys)
      (sort keys (lambda (x y)
		   (if (= (length (cdr x)) (length (cdr y)))
		       (> (length (car x)) 0)
		       (<= (length (cdr x)) (length (cdr y)))))))

    ))
