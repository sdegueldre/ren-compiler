module Ren.Compiler.Optimise.Module exposing
    ( optimise
    , removeUnusedDeclarations
    , removeUnusedExposedImports
    , removeUnusedImports
    , simplifyDeclarations
    )

-- IMPORTS ---------------------------------------------------------------------

import Ren.Compiler.Optimise.Declaration as Declaration
import Ren.Data.Declaration as Declaration exposing (Declaration(..))
import Ren.Data.Declaration.Visibility exposing (Visibility(..))
import Ren.Data.Expression.Pattern as Pattern
import Ren.Data.Module exposing (Module(..))
import Ren.Data.Module.Import exposing (Import(..))



-- RUNNING OPTIMISATIONS -------------------------------------------------------


{-| -}
optimise : Module -> Module
optimise =
    apply
        [ removeUnusedImports
        , removeUnusedExposedImports
        , removeUnusedDeclarations
        , simplifyDeclarations
        ]


{-| -}
apply : List (Module -> Maybe Module) -> Module -> Module
apply optimisations module_ =
    case optimisations of
        _ :: _ ->
            module_
                |> List.foldl or (always Nothing) optimisations
                |> Maybe.map (apply optimisations)
                |> Maybe.withDefault module_

        [] ->
            module_


{-| -}
or : (Module -> Maybe Module) -> (Module -> Maybe Module) -> Module -> Maybe Module
or f g m =
    f m |> Maybe.map Just |> Maybe.withDefault (g m)



-- OPTIMISATIONS: REMOVE UNUSED IMPORTS ----------------------------------------


{-| -}
removeUnusedImports : Module -> Maybe Module
removeUnusedImports (Module data) =
    List.filterMap (pruneImport data.declarations) data.imports
        |> (\imports ->
                if imports == data.imports then
                    Nothing

                else
                    Just <| Module { data | imports = imports }
           )


{-| -}
pruneImport : List Declaration -> Import -> Maybe Import
pruneImport declarations (Import ({ name, exposed } as data)) =
    case ( isImportNamespaceUsed declarations name, List.isEmpty exposed ) of
        -- Imported namespace is unused and nothing is exposed by the import.
        -- That means it's safe to remove it entirely.
        ( False, True ) ->
            Nothing

        -- Imported namespace is unused but something is exposed by the import,
        -- By setting the name to empty, we won't emit a useless import later on.
        ( False, False ) ->
            Just <| Import { data | name = [] }

        -- Imported namespace is used. Leave it untouched.
        _ ->
            Just <| Import data


{-| -}
isImportNamespaceUsed : List Declaration -> List String -> Bool
isImportNamespaceUsed declarations namespace =
    List.any (Declaration.referencesModule namespace) declarations



-- OPTIMISATIONS: REMOVE UNUSED EXPOSED IMPORTS --------------------------------


{-| -}
removeUnusedExposedImports : Module -> Maybe Module
removeUnusedExposedImports (Module data) =
    List.map (pruneExposedNames data.declarations) data.imports
        |> (\imports ->
                if imports == data.imports then
                    Nothing

                else
                    Just <| Module { data | imports = imports }
           )


{-| -}
pruneExposedNames : List Declaration -> Import -> Import
pruneExposedNames declarations (Import ({ exposed } as data)) =
    Import { data | exposed = List.filter (isNameUsed declarations) exposed }


{-| -}
isNameUsed : List Declaration -> String -> Bool
isNameUsed declarations name =
    List.any (Declaration.referencesName name) declarations



-- OPTIMISATION: REMOVE UNUSED DECLARATIONS ------------------------------------


{-| -}
removeUnusedDeclarations : Module -> Maybe Module
removeUnusedDeclarations (Module data) =
    List.filter (isDeclarationUsed data.declarations) data.declarations
        |> (\declarations ->
                if declarations == data.declarations then
                    Nothing

                else
                    Just <| Module { data | declarations = declarations }
           )


isDeclarationUsed : List Declaration -> Declaration -> Bool
isDeclarationUsed declarations declaration =
    if Declaration.visibility declaration == Public then
        True

    else
        let
            name =
                Declaration.name declaration

            names =
                Pattern.names name

            referencesAny d =
                List.any (\n -> Declaration.referencesName n d) names
        in
        declarations
            |> List.filter (Declaration.name >> (/=) name)
            |> List.any referencesAny



-- OPTIMISATION: SIMPLIFY DECLARATIONS -----------------------------------------


{-| -}
simplifyDeclarations : Module -> Maybe Module
simplifyDeclarations (Module data) =
    List.map Declaration.optimise data.declarations
        |> (\declarations ->
                if declarations == data.declarations then
                    Nothing

                else
                    Just <| Module { data | declarations = declarations }
           )
