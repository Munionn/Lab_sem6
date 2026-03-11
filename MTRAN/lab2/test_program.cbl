      * Test comment: covering all lexical elements of the COBOL lexer
       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEXTEST.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 NUM1 PIC 9(4)V99 VALUE 123.45.
       01 NUM2 PIC 9(3) VALUE 100.
       01 RESULT PIC 9(5)V99.
       01 NAME PIC X(20) VALUE "TEST-STRING".
       01 COUNTER PIC 99 VALUE 0.
       01 FLAG PIC 9 VALUE 1.

       PROCEDURE DIVISION.
       MAIN-PROC.
           DISPLAY "Starting program".

           COMPUTE RESULT = (NUM1 + NUM2) * 0.98.
           COMPUTE RESULT = NUM1 - NUM2.
           COMPUTE RESULT = NUM1 / 2.

           ADD 10 TO COUNTER; SUBTRACT 5 FROM COUNTER.
           MULTIPLY NUM2 BY 2 GIVING RESULT.
           DIVIDE NUM1 BY 3 GIVING RESULT.

           ADD NUM1, NUM2 GIVING RESULT.

           IF COUNTER > 0 AND FLAG = 1 THEN
               DISPLAY "Counter is positive"
           ELSE
               DISPLAY "Counter is zero or negative"
           END-IF.

           IF NUM1 < NUM2
               DISPLAY "NUM1 less than NUM2"
           END-IF.
           IF NUM1 >= 100
               DISPLAY "NUM1 greater or equal 100"
           END-IF.
           IF NUM2 <= 200
               DISPLAY "NUM2 less or equal 200"
           END-IF.
           IF FLAG <> 0
               DISPLAY "FLAG not zero"
           END-IF.

           IF NOT (FLAG = 0) OR COUNTER > 3 THEN
               DISPLAY "OR and NOT and THEN covered"
           END-IF.

           MOVE NAME(1:5) TO NAME.

           PERFORM VARYING COUNTER FROM 1 BY 1
               UNTIL COUNTER > 5
               DISPLAY COUNTER
           END-PERFORM.

           ACCEPT NAME.
           MOVE 999.99 TO RESULT.

           STOP RUN.
