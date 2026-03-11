open System
open System.IO
open System.Text.RegularExpressions

type TokenType =
    | Keyword
    | Identifier
    | NumericConstant
    | StringConstant
    | Operator
    | Delimiter
    | Comment
    | Unknown

// Лексема
type Token = {
    Type: TokenType
    Value: string
    Line: int
    Column: int
}

type Tables = {
    Keywords: Map<string, int>
    Identifiers: Map<string, int * string> 
    Constants: Map<string, int * string>   
    Operators: Map<string, int>
    Delimiters: Map<string, int>
}

let keywords = Set.ofList [
    "IDENTIFICATION"; "DIVISION"; "PROGRAM-ID"; "DATA"; "WORKING-STORAGE"
    "SECTION"; "PROCEDURE"; "PIC"; "VALUE"; "MOVE"; "TO"; "ADD"; "SUBTRACT"
    "MULTIPLY"; "DIVIDE"; "COMPUTE"; "IF"; "ELSE"; "END-IF"; "PERFORM"
    "UNTIL"; "DISPLAY"; "ACCEPT"; "STOP"; "RUN"; "FROM"; "BY"; "VARYING"
    "GIVING"; "AND"; "OR"; "NOT"; "THEN"; "END-PERFORM"
]

let operators = Set.ofList [
    "+"; "-"; "*"; "/"; "="; ">"; "<"; ">="; "<="; "<>"
]

let delimiters = Set.ofList [
    "."; ","; "("; ")"; ":"; ";"
]

let isNumeric (s: string) =
    Regex.IsMatch(s, @"^-?\d+(\.\d+)?(E[+-]?\d+)?$", RegexOptions.IgnoreCase)

let isStringConstant (s: string) =
    s.StartsWith("\"") && s.EndsWith("\"")

let isIdentifier (s: string) =
    Regex.IsMatch(s, @"^[A-Z][A-Z0-9-]*$")

let tokenizeLine (lineNum: int) (line: string) =
    let isComment = line.Length > 6 && line.[6] = '*'
    if isComment then
        [{ Type = Comment; Value = line.Trim(); Line = lineNum; Column = 0 }]
    else
       
        let pattern = @"""[^""]*""|>=|<=|<>|[A-Za-z][A-Za-z0-9-]*|\d+(\.\d+)?|[+\-*/=><]|[.,():;]|[^\s]"
        [
            for m in Regex.Matches(line, pattern) do
                let value = m.Value
                let upperValue = value.ToUpper()
                let tokenType =
                    if value.StartsWith("\"") && value.EndsWith("\"") && value.Length >= 2 then StringConstant
                    elif keywords.Contains(upperValue) then Keyword
                    elif Regex.IsMatch(value, @"^\d+(\.\d+)?$") then NumericConstant
                    elif operators.Contains(value) then Operator
                    elif delimiters.Contains(value) then Delimiter
                    elif isIdentifier upperValue then Identifier
                    else Unknown
                yield { Type = tokenType
                        Value = if tokenType = StringConstant then value else upperValue
                        Line = lineNum
                        Column = m.Index }
        ]

let buildTables (tokens: Token list) =
    let mutable kwMap = Map.empty
    let mutable idMap = Map.empty
    let mutable constMap = Map.empty
    let mutable opMap = Map.empty
    let mutable delimMap = Map.empty

    let mutable kwCounter = 1
    let mutable idCounter = 1
    let mutable constCounter = 1
    let mutable opCounter = 1
    let mutable delimCounter = 1

    for token in tokens do
        match token.Type with
        | Keyword ->
            if not (kwMap.ContainsKey(token.Value.ToUpper())) then
                kwMap <- kwMap.Add(token.Value.ToUpper(), kwCounter)
                kwCounter <- kwCounter + 1
        | Identifier ->
            if not (idMap.ContainsKey(token.Value)) then
                idMap <- idMap.Add(token.Value, (idCounter, "Идентификатор"))
                idCounter <- idCounter + 1
        | NumericConstant ->
            if not (constMap.ContainsKey(token.Value)) then
                constMap <- constMap.Add(token.Value, (constCounter, "Числовая константа"))
                constCounter <- constCounter + 1
        | StringConstant ->
            if not (constMap.ContainsKey(token.Value)) then
                constMap <- constMap.Add(token.Value, (constCounter, "Строковая константа"))
                constCounter <- constCounter + 1
        | Operator ->
            if not (opMap.ContainsKey(token.Value)) then
                opMap <- opMap.Add(token.Value, opCounter)
                opCounter <- opCounter + 1
        | Delimiter ->
            if not (delimMap.ContainsKey(token.Value)) then
                delimMap <- delimMap.Add(token.Value, delimCounter)
                delimCounter <- delimCounter + 1
        | _ -> ()

    { Keywords = kwMap; Identifiers = idMap; Constants = constMap; Operators = opMap; Delimiters = delimMap }

let printTables (tables: Tables) =
    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ТАБЛИЦА КЛЮЧЕВЫХ СЛОВ                            ║"
    printfn "╠════════╦═══════════════════════════════════════════════════╣"
    printfn "║ Номер  ║ Ключевое слово                                    ║"
    printfn "╠════════╬═══════════════════════════════════════════════════╣"
    tables.Keywords |> Map.iter (fun k v -> printfn "║ %-6d ║ %-49s ║" v k)
    printfn "╚════════╩═══════════════════════════════════════════════════╝"

    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ТАБЛИЦА ИДЕНТИФИКАТОРОВ                          ║"
    printfn "╠════════╦═══════════════════════════╦═══════════════════════╣"
    printfn "║ Номер  ║ Идентификатор             ║ Тип                   ║"
    printfn "╠════════╬═══════════════════════════╬═══════════════════════╣"
    tables.Identifiers |> Map.iter (fun k (num, typ) -> printfn "║ %-6d ║ %-25s ║ %-21s ║" num k typ)
    printfn "╚════════╩═══════════════════════════╩═══════════════════════╝"

    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ТАБЛИЦА КОНСТАНТ                                 ║"
    printfn "╠════════╦═══════════════════════════╦═══════════════════════╣"
    printfn "║ Номер  ║ Константа                 ║ Тип                   ║"
    printfn "╠════════╬═══════════════════════════╬═══════════════════════╣"
    tables.Constants |> Map.iter (fun k (num, typ) -> printfn "║ %-6d ║ %-25s ║ %-21s ║" num k typ)
    printfn "╚════════╩═══════════════════════════╩═══════════════════════╝"

    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ТАБЛИЦА ОПЕРАТОРОВ                               ║"
    printfn "╠════════╦═══════════════════════════════════════════════════╣"
    printfn "║ Номер  ║ Оператор                                          ║"
    printfn "╠════════╬═══════════════════════════════════════════════════╣"
    tables.Operators |> Map.iter (fun k v -> printfn "║ %-6d ║ %-49s ║" v k)
    printfn "╚════════╩═══════════════════════════════════════════════════╝"

    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ТАБЛИЦА РАЗДЕЛИТЕЛЕЙ                             ║"
    printfn "╠════════╦═══════════════════════════════════════════════════╣"
    printfn "║ Номер  ║ Разделитель                                       ║"
    printfn "╠════════╬═══════════════════════════════════════════════════╣"
    tables.Delimiters |> Map.iter (fun k v -> printfn "║ %-6d ║ %-49s ║" v k)
    printfn "╚════════╩═══════════════════════════════════════════════════╝"

// Вывод последовательности лексем
let printTokenSequence (tokens: Token list) (tables: Tables) =
    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ПОСЛЕДОВАТЕЛЬНОСТЬ ЛЕКСЕМ                        ║"
    printfn "╚════════════════════════════════════════════════════════════╝\n"

    let mutable sequence = []
    for token in tokens do
        match token.Type with
        | Keyword ->
            let num = tables.Keywords.[token.Value.ToUpper()]
            sequence <- sprintf "<КС%d>" num :: sequence
        | Identifier ->
            let (num, _) = tables.Identifiers.[token.Value]
            sequence <- sprintf "<ИД%d>" num :: sequence
        | NumericConstant | StringConstant ->
            let (num, _) = tables.Constants.[token.Value]
            sequence <- sprintf "<КОНСТ%d>" num :: sequence
        | Operator ->
            sequence <- token.Value :: sequence
        | Delimiter ->
            sequence <- token.Value :: sequence
        | Comment -> ()
        | Unknown ->
            sequence <- sprintf "<ОШИБКА:%s>" token.Value :: sequence

    printfn "%s\n" (String.Join(" ", List.rev sequence))

// Обнаружение ошибок
let detectErrors (tokens: Token list) =
    printfn "\n╔════════════════════════════════════════════════════════════╗"
    printfn "║           ОБНАРУЖЕННЫЕ ЛЕКСИЧЕСКИЕ ОШИБКИ                  ║"
    printfn "╚════════════════════════════════════════════════════════════╝\n"

    let errors = tokens |> List.filter (fun t -> t.Type = Unknown)

    if errors.IsEmpty then
        printfn "Лексических ошибок не обнаружено.\n"
    else
        for error in errors do
            printfn "❌ ОШИБКА на строке %d, позиция %d: '%s'" error.Line error.Column error.Value
        printfn ""

let analyze (inputFile: string) =
    if not (File.Exists(inputFile)) then
        printfn "Ошибка: файл '%s' не найден!" inputFile
    else
        printfn "╔════════════════════════════════════════════════════════════╗"
        printfn "║   ЛЕКСИЧЕСКИЙ АНАЛИЗАТОР COBOL                             ║"
        printfn "║   Входной файл: %-42s ║" (Path.GetFileName(inputFile))
        printfn "╚════════════════════════════════════════════════════════════╝\n"

        let lines = File.ReadAllLines(inputFile)
        let mutable allTokens = []

        for i = 0 to lines.Length - 1 do
            let tokens = tokenizeLine (i + 1) lines.[i]
            allTokens <- allTokens @ tokens

        let tables = buildTables allTokens

        printTables tables

        printTokenSequence allTokens tables

        detectErrors allTokens

        printfn "Анализ завершен успешно!"

let inputFile =
    if fsi.CommandLineArgs.Length > 1 then
        fsi.CommandLineArgs.[1]
    else
        "test_program.cbl"

analyze inputFile
