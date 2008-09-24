scm
;
; cgw-fan.scm
;
; Implements fanouts, comparators and fan-ins
;
; Fan-out simple repeats an incoming stream onto two outgoing streams
; Fan-in compares two input streams, and copies one to the output only
;    if the two inputs agree.
; The comparator applies a function to a pair of input streams, to
;    produce an output.
;
; Copyright (c) 2008 Linas Vepstas <linasvepstas@gmail.com>
;
; --------------------------------------------------------------------
;
; wire-fan-out a-wire b-wire c-wire
;
; Given a stream on any one of the wires, repeat it onto the other two.
; This function is the "inverse" of wire-fan-in, in that it makes two
; copies of a stream, whereas wire-fan-in reassembles the two copies.
;
(define (wire-fan-out a-wire b-wire c-wire)

	(let ((myname ""))
		; Take the input stream, pass it to the output streams.
		(define (fan in-wire a-out-wire b-out-wire)
			(let ((in-stream (wire-take-stream in-wire)))
				(wire-connect a-out-wire me)
				(wire-connect b-out-wire me)
				(wire-set-stream! a-out-wire in-stream me)
				(wire-set-stream! b-out-wire in-stream me)
			)
		)
	
		(define (process-msg)
			(cond
				((and 
						(wire-has-stream? a-wire)
						(not (wire-has-stream? b-wire))
						(not (wire-has-stream? c-wire))
					)
					(fan a-wire b-wire c-wire)
				)
				((and 
						(not (wire-has-stream? a-wire))
						(wire-has-stream? b-wire)
						(not (wire-has-stream? c-wire))
					)
					(fan b-wire c-wire a-wire)
				)
				((and 
						(not (wire-has-stream? a-wire))
						(not (wire-has-stream? b-wire))
						(wire-has-stream? c-wire)
					)
					(fan c-wire a-wire b-wire)
				)
			)
		)

		(define (me msg)
			(cond 
				((eq? msg wire-assert-msg)
					(process-msg)
				)
				((eq? msg wire-float-msg)
					;; do nothing
				)
				(else
					(default-dispatcher msg 'wire-fan-out myname)
				)
			)
		)

		(wire-connect a-wire me)
		(wire-connect b-wire me)
		(wire-connect c-wire me)
		me
	)
)

; --------------------------------------------------------------------
;
; wire-pair-fan-out
;
; Given an incoming stream of pairs, split it into two streams, with 
; the car part sent out on the 'out-car-wire' and the cdr part sent
; out on the 'out-cdr-wire'.
;
(define (wire-pair-fan-out in-pair-wire out-car-wire out-cdr-wire)

	(define (carfilter item) (list (car item)))
	(define (cdrfilter item) (list (cdr item)))
	(define carw (make-wire))
	(define cdrw (make-wire))
	(wire-transceiver carw out-car-wire carfilter)
	(wire-transceiver cdrw out-cdr-wire cdrfilter)
	(wire-fan-out (in-pair-wire carw cdrw))
)

;
; --------------------------------------------------------------------
;
; wire-fan-in a-wire b-wire c-wire
;
; Given a stream on any two wires, compare the two streams,
; and repeat only those parts of the streams that agree with
; each-other on the third wire.
;
; Example usage:
; Combining fan-out with fan-in should have no effect, so that, 
; for example, the code 
;
;   (define wire-one (make-wire))
;   (define wire-two (make-wire))
;   (wire-fan-in out-wire wire-one wire-two)
;   (wire-fan-out wire-two wire-in wire-one)
;
; results in wire-out having exactly the same stream as wire-in.
;
(define (wire-fan-in a-wire b-wire c-wire)
	(define (compare-func elt-one elt-two)

		;; a bit o debugging code
		;;(if (eq? elt-one elt-two)
		;;	(display "Bravo! match!\n")
		;;	(display "Oh No Mr. Bill!! mis-match!\n")
		;;)
		(if (eq? elt-one elt-two)
			(list elt-one)
			'()
		)
	)
	(wire-comparator a-wire b-wire c-wire compare-func)
)

; --------------------------------------------------------------------
;
; wire-comparator a-wire b-wire c-wire
;
; Compare input streams on any two wires, presenting an output stream
; on the third wire. The function 'compare-func' is used to generate
; the output stream: it must take two elements as input, and produce
; a list of elements as output (or produce a null list).  This function
; is entirely analogous to wire-transciever, except that the transformation
; function takes two inputs.
;
(define (wire-comparator a-wire b-wire c-wire compare-func)

	(let ((myname "")
			(a-in-stream stream-null)
			(b-in-stream stream-null)
			)

		; Define a generic producer function for a pair of streams. This
		; producer pulls an element off of each input stream, and applies
		; the function 'xform-func' to produce an output. The 'xform-func'
		; should produce a list of elements; these are then posted.
		(define (producer state xform-func)
			; If we are here, we're being forced.
			(if (null? state)
				(if (or
						(stream-null? a-in-stream)
						(stream-null? b-in-stream)
					)
					#f ; we are done, one of the other stream has been drained dry
					; else grab an element from each input-stream
					(let ((a-atom (stream-car a-in-stream))
							(b-atom (stream-car b-in-stream)))
						(set! a-in-stream (stream-cdr a-in-stream))
						(set! b-in-stream (stream-cdr b-in-stream))
						(if (or (null? a-atom) (null? b-atom))
							(error "Unexpected empty stream! wire-fan-in")
							(producer (xform-func a-atom b-atom) xform-func)
						)
					)
				)
				; else state is a list of elements, so keep letting 'er rip.
				state
			)
		)

		; create a stream, useing the producer function
		(define (mkstrm)
			(make-stream (lambda (state) (producer state compare-func)) '())
		)

		; Compare two input streams, only allow matches to pass
		(define (fan-in a-in-wire b-in-wire out-wire)
			(set! a-in-stream (wire-take-stream a-in-wire))
			(set! b-in-stream (wire-take-stream b-in-wire))
			(wire-set-stream! out-wire (mkstrm) me)
		)
	
		(define (process-msg)
			(cond
				((and 
						(wire-has-stream? a-wire)
						(wire-has-stream? b-wire)
						(not (wire-has-stream? c-wire))
					)
					(fan-in a-wire b-wire c-wire)
				)
				((and 
						(wire-has-stream? a-wire)
						(not (wire-has-stream? b-wire))
						(wire-has-stream? c-wire)
					)
					(fan-in c-wire a-wire b-wire)
				)
				((and 
						(not (wire-has-stream? a-wire))
						(wire-has-stream? b-wire)
						(wire-has-stream? c-wire)
					)
					(fan-in b-wire c-wire a-wire)
				)
				((and 
						(wire-has-stream? a-wire)
						(wire-has-stream? b-wire)
						(wire-has-stream? c-wire)
					)
					(error "All three wires have streams! -- wire-fan-in")
				)
			)
		)

		(define (me msg)
			(cond 
				((eq? msg wire-assert-msg)
					(process-msg)
				)
				((eq? msg wire-float-msg)
					;; do nothing
				)
				(else
					(default-dispatcher msg 'wire-fan myname)
				)
			)
		)

		(wire-connect a-wire me)
		(wire-connect b-wire me)
		(wire-connect c-wire me)
		me
	)
)

; --------------------------------------------------------------------
.
exit
