module Ren.Stage.Emit exposing (..)

{-| -}

-- IMPORTS ---------------------------------------------------------------------

import Pretty
import Ren.Ast.Expr as Expr exposing (Expr)
import Ren.Ast.JavaScript as JavaScript exposing (precedence)
import Ren.Data.Declaration as Declaration exposing (Declaration)
import Ren.Data.Import as Import exposing (Import)
import Ren.Data.Module exposing (Module)
import Util.Math



--


emit : Int -> Metadata -> Module -> String
emit width meta mod =
    Pretty.pretty width <| fromModule meta mod


emitDeclaration : Int -> Declaration -> String
emitDeclaration width decl =
    Pretty.pretty width <| fromDeclaration decl


emitExpr : Int -> Expr -> String
emitExpr width expr =
    Pretty.pretty width <| fromStatement <| JavaScript.fromExpr <| Expr.desugar expr



-- TYPES -----------------------------------------------------------------------


{-| The `Pretty.Doc` type has a type variable `t` used to tag strings in a document
for more fine-tuned rendering. We don't need any of that so instead of carrying
round a pointless type variable we'll just fill it in as `()` and use this alias
instead.
-}
type alias Doc =
    Pretty.Doc ()


type alias Metadata =
    { name : String
    , root : String
    , includeFFI : Bool
    }



-- CONSTRUCTORS ----------------------------------------------------------------


fromModule : Metadata -> Module -> Doc
fromModule meta mod =
    let
        ffiImport =
            concat
                [ Pretty.string "import"
                , Pretty.space
                , Pretty.char '*'
                , Pretty.space
                , Pretty.string "as"
                , Pretty.space
                , Pretty.string "$FFI"
                , Pretty.space
                , Pretty.string "from"
                , Pretty.space
                , Pretty.char '\''
                , Pretty.string <| "./" ++ meta.name ++ ".ffi.js"
                , Pretty.char '\''
                ]
    in
    Pretty.join doubleline <|
        [ mod.imports
            |> List.map (fromImport meta)
            |> (::) (when meta.includeFFI ffiImport)
            |> Pretty.join Pretty.line
        , mod.declarations
            |> List.map fromDeclaration
            |> Pretty.join doubleline
        ]


fromImport : Metadata -> Import -> Doc
fromImport meta imp =
    let
        path =
            if Import.isPackage imp then
                meta.root ++ "/.ren/pkg/" ++ imp.path

            else
                imp.path
    in
    case ( imp.name, imp.unqualified ) of
        ( [], [] ) ->
            concat
                [ Pretty.string "import"
                , Pretty.space
                , Pretty.char '\''
                , Pretty.string path
                , Pretty.char '\''
                ]

        ( name, [] ) ->
            concat
                [ Pretty.string "import"
                , Pretty.space
                , Pretty.char '*'
                , Pretty.space
                , Pretty.string "as"
                , Pretty.space
                , Pretty.string <| String.join "$" name
                , Pretty.space
                , Pretty.string "from"
                , Pretty.space
                , Pretty.char '\''
                , Pretty.string path
                , Pretty.char '\''
                ]

        ( [], unqualified ) ->
            concat
                [ Pretty.string "import"
                , Pretty.space
                , Pretty.char '{'
                , Pretty.join (Pretty.char ',') <| List.map Pretty.string unqualified
                , Pretty.char '}'
                , Pretty.space
                , Pretty.string "from"
                , Pretty.space
                , Pretty.char '\''
                , Pretty.string path
                , Pretty.char '\''
                ]

        -- Because of the way JavaScript imports work, we'll need two separate
        -- import statements if we want to qualify an entire module under a specific
        -- name *and* introduce some unqualified bindings.
        --
        -- To save on duplication, we'll just call the `fromImport` again but
        -- clear out the `unqualified` and `name` fields respectively to emit
        -- just one import statement on each line.
        ( _, _ ) ->
            Pretty.join Pretty.line
                [ fromImport meta { imp | unqualified = [] }
                , fromImport meta { imp | name = [] }
                ]


fromDeclaration : Declaration -> Doc
fromDeclaration dec =
    case dec of
        Declaration.Let pub name expr ->
            concat
                [ when pub <| Pretty.string "export "
                , case JavaScript.fromExpr expr of
                    JavaScript.Expr (JavaScript.Arrow arg body) ->
                        concat
                            [ Pretty.string "function"
                            , Pretty.space
                            , Pretty.string name
                            , Pretty.space
                            , Pretty.char '('
                            , Pretty.string arg
                            , Pretty.char ')'
                            , Pretty.space
                            , block body
                            ]

                    _ ->
                        concat
                            [ Pretty.string "const"
                            , Pretty.space
                            , Pretty.string name
                            , Pretty.space
                            , Pretty.string "="
                            , Pretty.space
                            , fromStatement <| JavaScript.fromExpr expr
                            ]
                ]

        Declaration.Ext pub name str ->
            concat
                [ when pub <| Pretty.string "export "
                , Pretty.string "const"
                , Pretty.space
                , Pretty.string name
                , Pretty.space
                , Pretty.char '='
                , Pretty.space
                , Pretty.string "$FFI"
                , Pretty.char '.'
                , Pretty.string str
                ]


fromStatement : JavaScript.Statement -> Doc
fromStatement stmt =
    case stmt of
        JavaScript.Block _ ->
            block stmt

        JavaScript.Comment cmt ->
            concat
                [ Pretty.string "//"
                , Pretty.space
                , Pretty.string cmt
                ]

        JavaScript.Const name expr ->
            concat
                [ Pretty.string "const"
                , Pretty.space
                , Pretty.string name
                , Pretty.space
                , Pretty.char '='
                , Pretty.space
                , fromExpression expr
                ]

        JavaScript.Expr expr ->
            fromExpression expr

        JavaScript.If cond then_ else_ ->
            concat
                [ Pretty.string "if"
                , Pretty.space
                , Pretty.parens <| fromExpression cond
                , Pretty.space
                , block then_
                , case else_ of
                    Just stmt_ ->
                        concat
                            [ Pretty.space
                            , Pretty.string "else"
                            , Pretty.space
                            , block stmt_
                            ]

                    Nothing ->
                        Pretty.empty
                ]

        JavaScript.Return expr ->
            concat
                [ Pretty.string "return"
                , Pretty.space
                , fromExpression expr
                ]

        JavaScript.Throw error ->
            concat
                [ Pretty.string "throw"
                , Pretty.space
                , Pretty.string "new Error"
                , Pretty.parens <| Pretty.surround (Pretty.char '`') (Pretty.char '`') <| Pretty.string error
                ]


fromExpression : JavaScript.Expression -> Doc
fromExpression expr =
    let
        precedence =
            JavaScript.precedence expr
    in
    case expr of
        JavaScript.Access expr_ [] ->
            fromExpression expr_

        JavaScript.Access expr_ keys ->
            concat
                [ parenthesise precedence expr_
                , Pretty.char '.'
                , Pretty.join (Pretty.char '.') (List.map Pretty.string keys)
                ]

        JavaScript.Add x y ->
            binop precedence x "+" y

        JavaScript.And x y ->
            binop precedence x "&&" y

        JavaScript.Array elements ->
            concat
                [ Pretty.char '['
                , List.map fromExpression elements
                    |> Pretty.join (Pretty.string ", ")
                , Pretty.char ']'
                ]

        JavaScript.Arrow arg body ->
            concat
                [ Pretty.char '('
                , Pretty.string arg
                , Pretty.char ')'
                , Pretty.space
                , Pretty.string "=>"
                , Pretty.space
                , case body of
                    JavaScript.Return expr_ ->
                        fromExpression expr_

                    _ ->
                        block body
                ]

        JavaScript.Bool True ->
            Pretty.string "true"

        JavaScript.Bool False ->
            Pretty.string "false"

        JavaScript.Call ((JavaScript.Arrow _ _) as fun) args ->
            concat
                [ Pretty.parens <| fromExpression fun
                , Pretty.join Pretty.empty <| List.map (Pretty.parens << fromExpression) args
                ]

        JavaScript.Call fun args ->
            concat
                [ fromExpression fun
                , Pretty.join Pretty.empty <| List.map (Pretty.parens << fromExpression) args
                ]

        JavaScript.Div x y ->
            binop precedence x "/" y

        JavaScript.Eq x y ->
            binop precedence x "==" y

        JavaScript.Gt x y ->
            binop precedence x ">" y

        JavaScript.Gte x y ->
            binop precedence x ">=" y

        JavaScript.IIFE Nothing stmt ->
            concat
                [ Pretty.char '('
                , Pretty.string "()"
                , Pretty.space
                , Pretty.string "=>"
                , Pretty.space
                , fromStatement stmt
                , Pretty.char ')'
                , Pretty.string "()"
                ]

        JavaScript.IIFE (Just ( name, expr_ )) stmt ->
            concat
                [ Pretty.char '('
                , Pretty.parens <| Pretty.string name
                , Pretty.space
                , Pretty.string "=>"
                , Pretty.space
                , fromStatement stmt
                , Pretty.char ')'
                , Pretty.parens <| fromExpression expr_
                ]

        JavaScript.Index expr_ idx ->
            concat
                [ parenthesise precedence expr_
                , Pretty.char '['
                , fromExpression idx
                , Pretty.char ']'
                ]

        JavaScript.Lt x y ->
            binop precedence x "<" y

        JavaScript.Lte x y ->
            binop precedence x "<=" y

        JavaScript.Mod x y ->
            binop precedence x "%" y

        JavaScript.Mul x y ->
            binop precedence x "*" y

        JavaScript.Neq x y ->
            binop precedence x "!=" y

        JavaScript.Number n ->
            Pretty.string <| String.fromFloat n

        JavaScript.Object fields ->
            concat
                [ Pretty.char '{'
                , fields
                    |> List.map
                        (\( k, v ) ->
                            if JavaScript.Var k == v then
                                fromExpression v

                            else
                                concat
                                    [ Pretty.string k
                                    , Pretty.char ':'
                                    , Pretty.space
                                    , fromExpression v
                                    ]
                        )
                    |> Pretty.join (Pretty.string ", ")
                , Pretty.char '}'
                ]

        JavaScript.Or x y ->
            binop precedence x "||" y

        JavaScript.Spread expr_ ->
            concat
                [ Pretty.string "..."
                , if JavaScript.precedence expr_ == Util.Math.infinite then
                    fromExpression expr_

                  else
                    Pretty.parens <| fromExpression expr_
                ]

        JavaScript.String s ->
            concat
                [ Pretty.string "`"
                , Pretty.string s
                , Pretty.string "`"
                ]

        JavaScript.Sub x y ->
            binop precedence x "-" y

        JavaScript.Typeof expr_ ->
            concat
                [ Pretty.string "typeof"
                , Pretty.space
                , parenthesise precedence expr_
                ]

        JavaScript.Undefined ->
            Pretty.string "undefined"

        JavaScript.Var name ->
            Pretty.string name



-- QUERIES ---------------------------------------------------------------------
-- MANIPULATIONS ---------------------------------------------------------------
-- UTILS -----------------------------------------------------------------------


block : JavaScript.Statement -> Doc
block stmt =
    let
        withSpacing s =
            case s of
                JavaScript.Block _ ->
                    concat [ Pretty.line, fromStatement s ]

                JavaScript.Comment _ ->
                    fromStatement s

                JavaScript.Const _ _ ->
                    fromStatement s

                JavaScript.Expr _ ->
                    concat [ Pretty.line, fromStatement s ]

                JavaScript.If _ _ _ ->
                    concat [ Pretty.line, fromStatement s ]

                JavaScript.Return _ ->
                    concat [ Pretty.line, fromStatement s ]

                JavaScript.Throw _ ->
                    concat [ Pretty.line, fromStatement s ]

        statements =
            case JavaScript.statements stmt of
                s :: rest ->
                    Pretty.indent 4 <|
                        Pretty.join Pretty.line <|
                            (fromStatement s :: List.map withSpacing rest)

                [] ->
                    Pretty.empty
    in
    concat
        [ Pretty.char '{'
        , Pretty.line
        , statements
        , Pretty.line
        , Pretty.char '}'
        ]


doubleline : Doc
doubleline =
    Pretty.line |> Pretty.a Pretty.line


binop : Int -> JavaScript.Expression -> String -> JavaScript.Expression -> Doc
binop precedence lhs op rhs =
    concat
        [ parenthesise precedence lhs
        , Pretty.space
        , Pretty.string op
        , Pretty.space
        , parenthesise precedence rhs
        ]


parenthesise : Int -> JavaScript.Expression -> Doc
parenthesise precedence expr =
    if precedence > JavaScript.precedence expr then
        Pretty.parens <| fromExpression expr

    else
        fromExpression expr


when : Bool -> Doc -> Doc
when true doc =
    if true then
        doc

    else
        Pretty.empty


concat : List Doc -> Doc
concat =
    List.foldl Pretty.a Pretty.empty
