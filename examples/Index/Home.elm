module Index.Home exposing (view)

import Color
import Element exposing (Element)
import Framework.Button as Button
import Framework.Card as Card
import Framework.Modifier exposing (Modifier(..))
import Framework.Typography as Typography
import PixelEngine exposing (Background)
import PixelEngine.Image as Image exposing (fromSrc)
import PixelEngine.Options as Options
import PixelEngine.Tile exposing (Tileset)


card : String -> Element msg
card name =
    Element.el [ Element.width <| Element.px 350 ] <|
        Card.simple <|
            Element.column
                [ Element.height <| Element.px 400
                , Element.spacing 20
                , Element.centerX
                ]
            <|
                [ Element.row
                    [ Element.width <| Element.fill
                    , Element.spaceEvenly
                    ]
                    [ Element.text name
                    , Button.buttonLink
                        []
                        ("https://github.com/Orasund/pixelengine/blob/master/examples/" ++ name ++ "/Main.elm")
                        "Source"
                    ]
                , Element.link []
                    { url = "#" ++ name
                    , label =
                        Element.image [ Element.width <| Element.fill ]
                            { src = "https://orasund.github.io/pixelengine/examples/" ++ name ++ "/" ++ "preview.png"
                            , description = "Preview"
                            }
                    }
                ]


view : { examples : List String, games : List String } -> Element msg
view { examples, games } =
    let
        windowWidth : Int
        windowWidth =
            200

        width : Float
        width =
            toFloat <| windowWidth

        font : Tileset
        font =
            { source = "https://orasund.github.io/pixelengine/fonts/RetroDeco8x16.png"
            , spriteWidth = 8
            , spriteHeight = 16
            }

        background : Background
        background =
            PixelEngine.colorBackground (Color.rgb255 222 238 214)
    in
    Element.column
        [ Element.spacing 50
        , Element.centerX
        ]
        [ Element.el
            [ Element.height <| Element.px <| 64 * 4
            , Element.centerX
            ]
          <|
            Element.html <|
                PixelEngine.toHtml
                    { width = width
                    , options =
                        Just
                            (Options.default
                                |> Options.withScale 4
                            )
                    }
                    [ PixelEngine.imageArea
                        { height = 64
                        , background = background
                        }
                        [ ( ( 32, 0 )
                          , fromSrc "https://orasund.github.io/pixelengine/docs/pixelengine-logo.png"
                          )
                        , ( ( width / 2, 8 ), Image.fromTextWithSpacing -2 "Create Games" font )
                        , ( ( width / 2, 32 ), Image.fromTextWithSpacing -3 "with Elm" font )
                        ]
                    ]
        , Element.column
            [ Element.spacing 10
            , Element.centerX
            ]
            [ Typography.h1 [ Element.centerX ] <| Element.text "Examples"
            , Element.wrappedRow [ Element.centerX, Element.spacing 10, Element.width <| Element.px <| (350 * 3) + 30 ]
                (examples |> List.map card)
            ]
        , Element.column
            [ Element.spacing 10
            , Element.centerX
            ]
            [ Typography.h1 [ Element.centerX ] <| Element.text "Games"
            , Element.wrappedRow [ Element.centerX, Element.spacing 10, Element.width <| Element.px <| (350 * 3) + 30 ]
                (games |> List.map card)
            ]
        ]
