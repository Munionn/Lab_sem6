      * COBOL Test Program with Lexical Errors
       IDENTIFICATION DIVISION.
       PROGRAM-ID. ERRTEST.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 VAR1 PIC 9(4) VALUE 12.34.56.
       01 NUM1 PIC 9(5)V99 VALUE 999.99.
       01 NUM2 PIC 9(3)   VALUE 100.

       01 VAR@2 PIC X(10).
       01 VAR#3 PIC 99.
       01 VAR!4 PIC 99.
       01 VAR%5 PIC X(5).
       01 VAR$6 PIC 9(5).
       01 3INVALID PIC 99.
       01 GOOD-VAR  PIC X(20) VALUE "Valid".
       01 RESULT    PIC 9(7)V99.
       77 CTR       PIC 9(3)  VALUE 0.

       01 VAR3 PIC X(30) VALUE "Unclosed string.
       01 VAR7 PIC X(10) VALUE 'HELLO'.
       01 MSG  PIC X(10) VALUE "OK".

       01 VAR8  PIC 9   VALUE ZERO.
       01 VAR9  PIC X   VALUE SPACE.
       01 VAR10 PIC X   VALUE QUOTE.

       PROCEDURE DIVISION.
       MAIN-PROC.

           COMPUTE RESULT = (NUM1 ++ NUM2).
           COMPUTE RESULT = NUM1 ** 2.
           IF CTR >= 0 AND CTR <= 10 AND CTR <> 5 AND CTR = 0
               DISPLAY "In range"
           END-IF.
           COMPUTE RESULT = (NUM1 + NUM2) - CTR * 2 / 1.

           MOVE 123..45 TO VAR1.
           MOVE $100 TO VAR1.
           MOVE 999.99 TO NUM1.

           DISPLAY "Test".
           DISPLAY "".

           ADD NUM1, NUM2 GIVING RESULT.
           DISPLAY "A"; DISPLAY "B".
           DISPLAY GOOD-VAR(1:5).
           COMPUTE RESULT = (NUM1 + NUM2) * CTR.

           STOP RUN.
