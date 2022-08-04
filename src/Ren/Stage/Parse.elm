module Ren.Stage.Parse exposing (..)

{-| -}

-- IMPORTS ---------------------------------------------------------------------

import Ren.Ast.Decl as Decl exposing (Decl)
import Ren.Ast.Expr as Expr exposing (Expr)
import Ren.Ast.Mod as Mod exposing (Mod)
import Ren.Control.Lexer as Lexer
import Ren.Control.Parser as Parser
import Ren.Data.Span exposing (Span)
import Ren.Data.Token exposing (Token)



--


mod : String -> Result String Mod
mod input =
    Lexer.run input
        |> Result.andThen
            (\stream ->
                stream
                    |> Parser.run Mod.parser
                    |> Result.mapError (\_ -> "parser error")
            )


decl : String -> Result String Decl
decl input =
    Lexer.run input
        |> Result.andThen
            (\stream ->
                stream
                    |> Parser.run Decl.parser
                    |> Result.mapError (\_ -> "parser error")
            )


expr : String -> Result String Expr
expr input =
    Lexer.run input
        |> Result.andThen
            (\stream ->
                stream
                    |> Parser.run (Expr.parser { inArgPosition = False })
                    |> Result.mapError (\_ -> "parser error")
            )



--


lex : String -> Result String (List ( Token, Span ))
lex =
    Lexer.run
