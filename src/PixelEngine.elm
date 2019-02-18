module PixelEngine exposing (PixelEngine, game, gameWithNoControls, gameWithCustomControls)

{-| This module takes care of all the wiring.

**If you are looking for the main module,
head over to [PixelEngine.Graphics](PixelEngine-Graphics).**

@docs PixelEngine, game, gameWithNoControls, gameWithCustomControls

-}

import Browser
import Browser.Dom as Dom
import Browser.Events as Events
import Html
import PixelEngine.Controls as Controls exposing (Input)
import PixelEngine.Graphics as Graphics exposing (Area, Options)
import PixelEngine.Graphics.Data.Options as OptionsData
import Task


{-| An alias for a PixelEngine program.

Your `main` function will have this type.

-}
type alias PixelEngine flag model msg =
    Program flag (Model model msg) (Msg msg)


type alias Config msg =
    { windowSize :
        Maybe
            { width : Float
            , height : Float
            }
    , controls : Maybe ( String -> Input, Input -> msg )
    }


type alias Model model msg =
    { modelContent : model
    , config : Config msg
    }


type Msg msg
    = Resize { width : Float, height : Float }
    | MsgContent msg


batch : ( model, Cmd msg ) -> Model model msg -> ( Model model msg, Cmd (Msg msg) )
batch ( modelContent, msg ) { config } =
    ( { modelContent = modelContent, config = config }, msg |> Cmd.map MsgContent )


updateFunction : (msg -> model -> ( model, Cmd msg )) -> Msg msg -> Model model msg -> ( Model model msg, Cmd (Msg msg) )
updateFunction update msg ({ modelContent, config } as model) =
    case msg of
        Resize windowSize ->
            ( { model
                | config =
                    { config
                        | windowSize = Just windowSize
                    }
              }
            , Cmd.none
            )

        MsgContent msgC ->
            model |> batch (update msgC modelContent)


subscriptionsFunction : (model -> Sub msg) -> Model model msg -> Sub (Msg msg)
subscriptionsFunction subscriptions { modelContent, config } =
    Sub.batch
        ([ subscriptions modelContent |> Sub.map MsgContent
         , Events.onResize <| \w h -> Resize { width = toFloat w, height = toFloat h }
         ]
            |> List.append
                (case config.controls of
                    Just ( _, controlsToMsg ) ->
                        [ Controls.basic controlsToMsg |> Sub.map MsgContent ]

                    Nothing ->
                        []
                )
        )


viewFunction : (model -> { title : String, options : Options msg, body : List (Area msg) }) -> Model model msg -> Browser.Document (Msg msg)
viewFunction view { modelContent, config } =
    let
        { windowSize, controls } =
            config

        { title, options, body } =
            view modelContent

        (OptionsData.Options { width, scale }) =
            options

        height =
            (toFloat <| scale) * Graphics.heightOf body
    in
    { title = title
    , body =
        [ (case windowSize of
            Just wS ->
                Graphics.view
                    (options
                        |> OptionsData.usingScale
                            (min (2 ^ (floor <| logBase 2 <| wS.height / height))
                                (2 ^ (floor <| logBase 2 <| wS.width / width))
                            )
                        |> (case controls of
                                Just ( _, controlsToMsg ) ->
                                    Controls.supportingMobile
                                        { windowSize = wS
                                        , controls = controlsToMsg
                                        }

                                Nothing ->
                                    identity
                           )
                    )
                    body

            Nothing ->
                Graphics.view options []
          )
            |> Html.map MsgContent
        ]
    }


initFunction : Maybe ( String -> Input, Input -> msg ) -> (flags -> ( model, Cmd msg )) -> (flags -> ( Model model msg, Cmd (Msg msg) ))
initFunction controls init =
    \flag ->
        let
            ( modelContent, msg ) =
                init flag
        in
        ( { modelContent = modelContent
          , config = { windowSize = Nothing, controls = controls }
          }
        , Cmd.batch
            [ msg |> Cmd.map MsgContent
            , Task.perform
                (\{ viewport } ->
                    let
                        { width, height } =
                            viewport
                    in
                    Resize { width = width, height = height }
                )
                Dom.getViewport
            ]
        )


gameMaybeWithCustomControls :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> { title : String, options : Options msg, body : List (Area msg) }
    , controls : Maybe ( String -> Input, Input -> msg )
    }
    -> Program flags (Model model msg) (Msg msg)
gameMaybeWithCustomControls { init, update, subscriptions, view, controls } =
    Browser.document
        { init =
            initFunction controls init
        , update =
            updateFunction update
        , subscriptions =
            subscriptionsFunction subscriptions
        , view =
            viewFunction view
        }


{-| A game using custom controls.

The default controls should be enough to start,
but maybe you want to write a spelling game,
or its nessesary that very specifc keys are used?

-}
gameWithCustomControls :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> { title : String, options : Options msg, body : List (Area msg) }
    , controls : ( String -> Input, Input -> msg )
    }
    -> Program flags (Model model msg) (Msg msg)
gameWithCustomControls { init, update, subscriptions, view, controls } =
    gameMaybeWithCustomControls
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , controls = Just controls
        }


{-| A game with no controls.

Use it just like `document` from [elm/browser](https://package.elm-lang.org/packages/elm/browser/latest/Browser).

-}
gameWithNoControls :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> { title : String, options : Options msg, body : List (Area msg) }
    }
    -> Program flags (Model model msg) (Msg msg)
gameWithNoControls { init, update, subscriptions, view } =
    gameMaybeWithCustomControls
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , controls = Nothing
        }


{-| A prewired PixelEngine frame.

Use it just like `document` from [elm/browser](https://package.elm-lang.org/packages/elm/browser/latest/Browser).

-}
game :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> { title : String, options : Options msg, body : List (Area msg) }
    , controls : Input -> msg
    }
    -> Program flags (Model model msg) (Msg msg)
game { init, update, subscriptions, view, controls } =
    gameMaybeWithCustomControls
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , controls = Just ( Controls.defaultLayout, controls )
        }
