#lang racket

(require parser-tools/lex
         (prefix-in re- parser-tools/lex-sre)
         parser-tools/yacc
	 "../parser.rkt" "../ast.rkt" "neon-ast.rkt")

(provide neon-parser%)

(define neon-parser%
  (class parser%
    (super-new)
    (inherit-field asm-parser asm-lexer)

    (define-tokens a (LABEL BLOCK WORD NUM))
    (define-empty-tokens b (EOF NOP TEXT COMMA DQUOTE HOLE 
                                HASH LCBRACK RCBRACK LSQBRACK RSQBRACK ! DOT))

    (define-lex-abbrevs
      (line-comment (re-: (re-: ";" (re-* (char-complement #\newline)))
                          #\newline)))

    (set! asm-lexer
       (lexer-src-pos
       ("nop"      (token-NOP))
       (".text"    (token-TEXT))
       (","        (token-COMMA))
       ("."        (token-DOT))
       ("\""       (token-DQUOTE))
       ("?"        (token-HOLE))
       ("#"        (token-HASH))
       ("{"        (token-LCBRACK))
       ("}"        (token-RCBRACK))
       ("["        (token-LSQBRACK))
       ("]"        (token-RSQBRACK))
       ("!"        (token-!))
       (identifier: (token-LABEL lexeme))
       (identifier (token-WORD lexeme))
       (snumber10  (token-NUM lexeme))
       (line-comment (position-token-token (asm-lexer input-port)))
       (whitespace   (position-token-token (asm-lexer input-port)))
       ((eof) (token-EOF))))

    (set! asm-parser
      (parser
       (start code)
       (end EOF)
       (error
        (lambda (tok-ok? tok-name tok-value start-pos end-pos)
          (raise-syntax-error 
           'parser
           (format "syntax error at '~a' in src l:~a c:~a"
                   tok-name
                   (position-line start-pos)
                   (position-col start-pos)))))
       
       (tokens a b)
       (src-pos)
       (grammar
        (words ((WORD) $1)
               ((NUM) $1)
               ((WORD words) (string-append $1 " " $2)))

        (arg  ((WORD) $1)
              ((DQUOTE words DQUOTE) (string-append "\"" $2 "\""))
              ((NUM) $1)
              ((HASH NUM) $2) ;;(string-append "#" $2))
              ((LCBRACK args RCBRACK) (list->vector $2)) ;; list inside list
              ((LSQBRACK args RSQBRACK) $2) ;; list inside list
              ((WORD LSQBRACK NUM RSQBRACK) (list $1 $3))
              )

        (args ((arg) (list $1))
              ((arg COMMA args) (cons $1 $3)))
        
        (opcode-type ((WORD) (list $1 #f #f))
                     ((DOT WORD) (list (string-append "." $2) #f #f))
                     ((WORD DOT WORD)
                      (if (string->number (substring $3 0 1))
                          (list $1 $3 #f)
                          (list $1 (substring $3 1) (substring $3 0 1))))
                     ((WORD DOT NUM) (list $1 $3 #f)))

        (instruction ((opcode-type args)
                      (new-inst (first $1)
                                (list->vector (flatten $2)) 
                                (second $1)
                                (third $1)))
                     ((opcode-type args !)
                      (new-inst (string-append (first $1) "!") 
                                (list->vector (flatten $2)) 
                                (second $1)
                                (third $1)))
                     
                     ((NOP)       (neon-inst "nop" (vector) #f #f))
                     ((TEXT)      (neon-inst ".text" (vector) #f #f))
                     ((HOLE)      (neon-inst #f #f #f #f)))
        (inst-list   (() (list))
                     ((instruction inst-list) (cons $1 $2)))

        (oneblock    ((BLOCK inst-list) (block (list->vector $2) #f 
                                               (substring $1 2))))
        (blocks      ((oneblock) (list $1))
                     ((oneblock blocks) (cons $1 $2)))
        

        (chunk  ((LABEL blocks)    (label $1 $2 #f))
                ((LABEL inst-list) (label $1 (block (list->vector $2) #f #f) #f)))
        
        (chunks ((chunk) (list $1))

                ((chunk chunks) (cons $1 $2)))

        (code   ((inst-list chunks) (cons (label #f (block (list->vector $1) #f #f) #f)
                                          $2))
                ((inst-list) (list->vector $1))
                )

        )))

    (define (new-inst op args byte type)
      (set! op (string-downcase op))
      (define last-arg (vector-ref args (sub1 (vector-length args))))
      
      (cond
       [(string->number last-arg)
        (set! op (string-append op "#"))]
       [(and (regexp-match #rx"vld" op) (= (vector-length args) 3))
        (set! op (string-append op "+offset"))])
      
      (neon-inst op args byte type))

    ))
      