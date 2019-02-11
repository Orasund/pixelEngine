module MiniWorldWar.Main exposing (main)

import MiniWorldWar.Board as Board exposing (Move, Unit)
import MiniWorldWar.Card as Card
import MiniWorldWar.Color as Color exposing (Color(..))
import MiniWorldWar.Continent as Continent exposing (Continent(..))
import MiniWorldWar.Direction as Direction exposing (Direction(..))
import MiniWorldWar.Game as Game exposing (Game, GameState(..))
import MiniWorldWar.Gui as Gui exposing (SelectGui)
import MiniWorldWar.Server as Server exposing (Response(..))
import MiniWorldWar.Server.Client as ClientServer exposing (ClientMsg(..))
import MiniWorldWar.Server.Guest as GuestServer exposing (GuestMsg(..))
import MiniWorldWar.Server.Host as HostServer exposing (HostMsg(..))
import MiniWorldWar.Server.WaitingHost as WaitingHostServer exposing (WaitingHostMsg(..))
import MiniWorldWar.Unit as Unit
import MiniWorldWar.View as View
import MiniWorldWar.View.TitleScreen as TitleScreenView
import MiniWorldWar.View.Unit as UnitView
import PixelEngine exposing (PixelEngine, game)
import PixelEngine.Controls exposing (Input(..))
import PixelEngine.Graphics as Graphics exposing (Area, Background, Options)
import PixelEngine.Graphics.Image as Image exposing (Image, image)
import PixelEngine.Graphics.Tile exposing (Tile, Tileset)
import Random exposing (Generator, Seed)
import Task
import Time exposing (Posix)


type alias Model =
    { game : Game
    , time : Posix
    , playerColor : Color
    , select : Maybe ( Continent, SelectGui )
    , ready : Bool
    , id : String
    }


type State
    = Client Model
    | Host ( Model, Seed )
    | WaitingHost ( { time : Posix, id : String }, Seed )
    | Guest Posix
    | FetchingTime


type GuestEvent
    = HostGame Seed


type BoardEvent
    = OpenSelectGui Continent
    | AddUnit
    | RemoveUnit
    | SwapUnits
    | ResetMove
    | SetMove Direction


type SpecificMsg response event
    = Response response
    | Event event


type Msg
    = GuestSpecific (SpecificMsg GuestMsg GuestEvent)
    | HostSpecific HostMsg
    | WaitingHostSpecific WaitingHostMsg
    | ClientSpecific ClientMsg
    | BoardSpecific BoardEvent
    | ServerSpecific (Response Never)
    | Update Posix
    | None


responseToMsg : (specificMsg -> Msg) -> Response specificMsg -> Msg
responseToMsg fun response =
    case response of
        Please msg ->
            fun msg

        Exit ->
            ServerSpecific Exit

        Reset ->
            ServerSpecific Reset

        Idle ->
            ServerSpecific Idle

        DropOpenGameTable ->
            ServerSpecific DropOpenGameTable

        DropRunningGameTable ->
            ServerSpecific DropRunningGameTable



{------------------------
   INIT
------------------------}


init : () -> ( State, Cmd Msg )
init _ =
    ( FetchingTime
    , Cmd.none
    )



{------------------------
   UPDATE
------------------------}


clientUpdate : ClientMsg -> Model -> ( State, Cmd Msg )
clientUpdate msg ({ time, id, game } as model) =
    let
        state : State
        state =
            Client model
    in
    case msg of
        WaitingForHost ->
            ( state
            , ClientServer.waitingForHost id game.lastUpdated
                |> Cmd.map (responseToMsg ClientSpecific)
            )

        UpdateGame ({ moveBoard } as newGame) ->
            case newGame.state of
                Running ->
                    ( Client
                        { model
                            | ready = False
                            , game = newGame
                        }
                    , Cmd.none
                    )

                HostReady ->
                    let
                        newerGame =
                            { game
                                | lastUpdated = time |> Time.posixToMillis
                                , state = BothReady
                            }
                    in
                    ( Client
                        { model
                            | game =
                                game
                                    --outdated Game -we wait for a newer one
                                    |> Game.addMoveBoard moveBoard
                                    |> (\g ->
                                            { g
                                                | state = BothReady
                                                , lastUpdated = time |> Time.posixToMillis
                                            }
                                       )
                        }
                    , ClientServer.submitMoveBoard newerGame id
                        |> Cmd.map (responseToMsg ClientSpecific)
                    )

                _ ->
                    ( Client { model | game = newGame, ready = False }
                    , ClientServer.endGame id time
                        |> Cmd.map (responseToMsg ClientSpecific)
                    )

        EndGame ->
            ( state
            , ClientServer.endGame id time
                |> Cmd.map (responseToMsg ClientSpecific)
            )

        UpdateGameTable table ->
            ( state
            , ClientServer.updateGameTable table
                |> Cmd.map (responseToMsg ClientSpecific)
            )

        Ready ->
            ( Client
                { model
                    | ready = True
                }
            , Cmd.none
            )


hostUpdate : HostMsg -> ( Model, Seed ) -> ( State, Cmd Msg )
hostUpdate msg (( { game, id, time } as model, seed ) as modelAndSeed) =
    let
        state : State
        state =
            Host modelAndSeed
    in
    case msg of
        Submit ->
            let
                newGame =
                    { game
                        | lastUpdated = time |> Time.posixToMillis
                        , state = HostReady
                    }
            in
            ( Host
                ( { model
                    | ready = True
                    , game = newGame
                  }
                , seed
                )
            , HostServer.submit id newGame
                |> Cmd.map (responseToMsg HostSpecific)
            )

        UpdateMoveBoard moveBoard ->
            ( Host
                ( { model
                    | game =
                        game
                            --outdated Game -we wait for a newer one
                            |> Game.addMoveBoard moveBoard
                            |> (\g -> { g | state = BothReady })
                  }
                , seed
                )
            , Cmd.none
            )

        WaitingForClient ->
            ( state
            , HostServer.waitingForClient id game.lastUpdated
                |> Cmd.map (responseToMsg HostSpecific)
            )


waitingHostUpdate : WaitingHostMsg -> ( { time : Posix, id : String }, Seed ) -> ( State, Cmd Msg )
waitingHostUpdate msg (( { time, id }, seed ) as timeAndSeed) =
    let
        state : State
        state =
            WaitingHost timeAndSeed

        defaultCase : ( State, Cmd Msg )
        defaultCase =
            ( state, Cmd.none )
    in
    case msg of
        WaitForOpponent ->
            ( state
            , WaitingHostServer.checkForOpponent id
                |> Cmd.map (responseToMsg WaitingHostSpecific)
            )

        CreateBoard game ->
            let
                ( newGame, newSeed ) =
                    seed
                        |> Random.step
                            (game |> Game.nextRound time)
            in
            ( Host
                ( { time = time
                  , id = id
                  , game = newGame
                  , select = Nothing
                  , playerColor = Red
                  , ready = False
                  }
                , newSeed
                )
            , newGame
                |> HostServer.submit id
                |> Cmd.map (responseToMsg HostSpecific)
            )


guestUpdate : SpecificMsg GuestMsg GuestEvent -> Posix -> ( State, Cmd Msg )
guestUpdate msg time =
    let
        state : State
        state =
            Guest time

        defaultCase : ( State, Cmd Msg )
        defaultCase =
            ( state, Cmd.none )

        game : Game
        game =
            time |> Time.posixToMillis |> Game.new
    in
    case msg of
        Response response ->
            case response of
                JoinGame id ->
                    ( Client
                        { game = game
                        , time = time
                        , id = id
                        , select = Nothing
                        , playerColor = Blue
                        , ready = True
                        }
                    , ClientServer.joinGame id game
                        |> Cmd.map (responseToMsg ClientSpecific)
                    )

                JoinOpenGame id ->
                    ( state
                    , GuestServer.joinOpenGame id
                        |> Cmd.map (responseToMsg (GuestSpecific << Response))
                    )

                CloseGame id ->
                    ( state
                    , GuestServer.closeGame id
                        |> Cmd.map (responseToMsg (GuestSpecific << Response))
                    )

                ReopenGame id ->
                    ( state
                    , GuestServer.reopenGame id
                        |> Cmd.map (responseToMsg (GuestSpecific << Response))
                    )

                FindOldGame ->
                    ( state
                    , GuestServer.findOldGame time
                        |> Cmd.map (responseToMsg (GuestSpecific << Response))
                    )

                CreateNewGame ->
                    ( state
                    , Random.generate
                        (GuestSpecific << Event << HostGame)
                        Random.independentSeed
                    )

                FindOpenGame ->
                    ( state
                    , GuestServer.findOpenGame time
                        |> Cmd.map (responseToMsg (GuestSpecific << Response))
                    )

        Event event ->
            case event of
                HostGame seed ->
                    let
                        ( id, newSeed ) =
                            Random.step
                                (Random.int Random.minInt Random.maxInt
                                    |> Random.map String.fromInt
                                )
                                seed
                    in
                    ( WaitingHost
                        ( { time = time
                          , id = id
                          }
                        , newSeed
                        )
                    , WaitingHostServer.hostGame id time
                        |> Cmd.map (responseToMsg WaitingHostSpecific)
                    )


updateBoard : BoardEvent -> Model -> Model
updateBoard msg ({ game, select } as model) =
    let
        { unitBoard, moveBoard } =
            game
    in
    case msg of
        OpenSelectGui continent ->
            case unitBoard |> Board.get continent of
                Just { amount } ->
                    { model
                        | select =
                            Just
                                ( continent
                                , { remaining = amount - 1
                                  , selected = 1
                                  }
                                )
                    }

                Nothing ->
                    model

        AddUnit ->
            case select of
                Just ( continent, { selected, remaining } ) ->
                    if remaining > 1 then
                        { model
                            | select =
                                Just
                                    ( continent
                                    , { remaining = remaining - 1
                                      , selected = selected + 1
                                      }
                                    )
                        }

                    else
                        model

                Nothing ->
                    model

        RemoveUnit ->
            case select of
                Just ( continent, { selected, remaining } ) ->
                    if selected > 1 then
                        { model
                            | select =
                                Just
                                    ( continent
                                    , { remaining = remaining + 1
                                      , selected = selected - 1
                                      }
                                    )
                        }

                    else
                        model

                Nothing ->
                    model

        SwapUnits ->
            case select of
                Just ( continent, { selected, remaining } ) ->
                    if selected > 0 then
                        { model
                            | select =
                                Just
                                    ( continent
                                    , { remaining = selected
                                      , selected = remaining
                                      }
                                    )
                        }

                    else
                        model

                Nothing ->
                    model

        ResetMove ->
            case select of
                Just ( continent, _ ) ->
                    { model
                        | game =
                            { game
                                | moveBoard =
                                    moveBoard
                                        |> Board.set continent Nothing
                            }
                        , select = Nothing
                    }

                Nothing ->
                    model

        SetMove direction ->
            case select of
                Just ( continent, { selected, remaining } ) ->
                    { model
                        | game =
                            { game
                                | moveBoard =
                                    moveBoard
                                        |> Board.set
                                            continent
                                            (Just
                                                { amount = selected
                                                , direction = direction
                                                }
                                            )
                            }
                        , select = Nothing
                    }

                Nothing ->
                    model


update : Msg -> State -> ( State, Cmd Msg )
update msg state =
    let
        defaultCase : ( State, Cmd Msg )
        defaultCase =
            ( state, Cmd.none )
    in
    case msg of
        ClientSpecific clientMsg ->
            case state of
                Client model ->
                    clientUpdate clientMsg model

                _ ->
                    defaultCase

        HostSpecific hostMsg ->
            case state of
                Host (( model, seed ) as modelAndSeed) ->
                    hostUpdate hostMsg modelAndSeed

                _ ->
                    defaultCase

        WaitingHostSpecific waitingHostMsg ->
            case state of
                WaitingHost timeAndSeed ->
                    waitingHostUpdate waitingHostMsg timeAndSeed

                _ ->
                    defaultCase

        GuestSpecific guestMsg ->
            case state of
                Guest time ->
                    guestUpdate guestMsg time

                _ ->
                    defaultCase

        BoardSpecific boardMsg ->
            case state of
                Client ({ ready } as model) ->
                    if ready then
                        defaultCase

                    else
                        ( Client <| updateBoard boardMsg model, Cmd.none )

                Host ( { ready } as model, seed ) ->
                    if ready then
                        defaultCase

                    else
                        ( Host <| ( updateBoard boardMsg model, seed ), Cmd.none )

                _ ->
                    defaultCase

        ServerSpecific serverMsg ->
            case serverMsg of
                DropOpenGameTable ->
                    ( state
                    , Server.dropOpenGameTable |> Cmd.map ServerSpecific
                    )

                DropRunningGameTable ->
                    ( state
                    , Server.dropRunningGameTable |> Cmd.map ServerSpecific
                    )

                Exit ->
                    ( state
                    , (case state of
                        Client { id } ->
                            ClientServer.exit id

                        Host ( { id }, _ ) ->
                            HostServer.exit id

                        WaitingHost ( { id }, _ ) ->
                            WaitingHostServer.exit id

                        Guest _ ->
                            GuestServer.exit

                        FetchingTime ->
                            GuestServer.exit
                      )
                        |> Cmd.map ServerSpecific
                    )

                Reset ->
                    init ()

                Please _ ->
                    defaultCase

                Idle ->
                    defaultCase

        Update time ->
            case state of
                Client ({ ready, id, game } as model) ->
                    ( Client { model | time = time }
                    , let
                        { lastUpdated } =
                            game
                      in
                      if ready then
                        ClientServer.waitingForHost id lastUpdated
                            |> Cmd.map (responseToMsg ClientSpecific)

                      else
                        Cmd.none
                    )

                Host ( { ready, id, game } as model, seed ) ->
                    let
                        { lastUpdated, moveBoard } =
                            game
                    in
                    if ready then
                        case game.state of
                            BothReady ->
                                let
                                    ( newGame, newSeed ) =
                                        seed
                                            |> Random.step (game |> Game.nextRound time)
                                in
                                ( Host
                                    ( { model
                                        | game = newGame
                                        , time = time
                                        , ready = False
                                      }
                                    , newSeed
                                    )
                                , HostServer.submit id newGame
                                    |> Cmd.map (responseToMsg HostSpecific)
                                )

                            _ ->
                                ( Host ( { model | time = time }, seed )
                                , HostServer.waitingForClient id lastUpdated
                                    |> Cmd.map (responseToMsg HostSpecific)
                                )

                    else
                        ( Host ( { model | time = time }, seed ), Cmd.none )

                WaitingHost ( { id }, seed ) ->
                    ( WaitingHost ( { id = id, time = time }, seed )
                    , WaitingHostServer.checkForOpponent id
                        |> Cmd.map (responseToMsg WaitingHostSpecific)
                    )

                Guest _ ->
                    ( Guest time, Cmd.none )

                FetchingTime ->
                    ( Guest time, Cmd.none )

        None ->
            defaultCase



{------------------------
   SUBSCRIPTIONS
------------------------}


subscriptions : State -> Sub Msg
subscriptions state =
    let
        updateSub : Sub Msg
        updateSub =
            Time.every (1 * 1000) Update
    in
    case state of
        FetchingTime ->
            updateSub

        Guest _ ->
            Sub.none

        WaitingHost _ ->
            updateSub

        Host _ ->
            updateSub

        Client _ ->
            updateSub



{------------------------
   CONTROLS
------------------------}


controls : Input -> Msg
controls _ =
    None



{------------------------
   VIEW
------------------------}


drawCard : Continent -> Maybe Unit -> Maybe ( ( Float, Float ), Image msg )
drawCard continent maybeUnit =
    maybeUnit
        |> Maybe.map
            (\{ color } ->
                ( View.continentToPosition continent
                , Card.card continent color
                )
            )


drawSelectGui : Continent -> SelectGui -> List ( ( Float, Float ), Image Msg )
drawSelectGui continent ({ selected, remaining } as selectGui) =
    let
        ( x, y ) =
            continent |> View.continentToPosition

        relativeCoord : ( Float, Float ) -> ( Float, Float )
        relativeCoord ( x1, y1 ) =
            ( x + 8 * x1, y + 3 + 8 * y1 )

        addUnitButton : List ( ( Float, Float ), Image Msg )
        addUnitButton =
            case remaining of
                1 ->
                    []

                _ ->
                    [ ( relativeCoord ( 3, 0 )
                      , Gui.addUnitButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific AddUnit
                                ]
                      )
                    ]

        swapUnitsButton : List ( ( Float, Float ), Image Msg )
        swapUnitsButton =
            [ ( relativeCoord ( 3, 1 )
              , Gui.swapUnitsButton
                    |> Image.withAttributes
                        [ Image.onClick <|
                            BoardSpecific SwapUnits
                        ]
              )
            ]

        removeUnitButton : List ( ( Float, Float ), Image Msg )
        removeUnitButton =
            case selected of
                1 ->
                    []

                _ ->
                    [ ( relativeCoord ( 3, 2 )
                      , Gui.removeUnitButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific RemoveUnit
                                ]
                      )
                    ]

        locationButtons : List ( ( Float, Float ), Image Msg )
        locationButtons =
            case continent of
                Asia ->
                    [ ( relativeCoord ( 1, 1 )
                      , Gui.centerCardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        ResetMove
                                ]
                      )
                    , ( relativeCoord ( 0, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Left
                                ]
                      )
                    , ( relativeCoord ( 2, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Right
                                ]
                      )
                    ]

                Africa ->
                    [ ( relativeCoord ( 1, 2 )
                      , Gui.centerCardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        ResetMove
                                ]
                      )
                    , ( relativeCoord ( 1, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Up
                                ]
                      )
                    , ( relativeCoord ( 0, 2 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Left
                                ]
                      )
                    ]

                SouthAmerica ->
                    [ ( relativeCoord ( 1, 2 )
                      , Gui.centerCardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        ResetMove
                                ]
                      )
                    , ( relativeCoord ( 1, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Up
                                ]
                      )
                    , ( relativeCoord ( 2, 2 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Right
                                ]
                      )
                    ]

                Europe ->
                    [ ( relativeCoord ( 1, 1 )
                      , Gui.centerCardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        ResetMove
                                ]
                      )
                    , ( relativeCoord ( 0, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Left
                                ]
                      )
                    , ( relativeCoord ( 2, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Right
                                ]
                      )
                    , ( relativeCoord ( 1, 2 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Down
                                ]
                      )
                    ]

                NorthAmerica ->
                    [ ( relativeCoord ( 1, 1 )
                      , Gui.centerCardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        ResetMove
                                ]
                      )
                    , ( relativeCoord ( 0, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Left
                                ]
                      )
                    , ( relativeCoord ( 2, 1 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Right
                                ]
                      )
                    , ( relativeCoord ( 1, 2 )
                      , Gui.cardButton
                            |> Image.withAttributes
                                [ Image.onClick <|
                                    BoardSpecific <|
                                        SetMove Down
                                ]
                      )
                    ]
    in
    List.concat
        [ [ ( ( x, y ), Gui.selectGui selectGui ) ]
        , addUnitButton
        , swapUnitsButton
        , removeUnitButton
        , locationButtons
        ]


drawModel : Msg -> Model -> List ( ( Float, Float ), Image Msg )
drawModel submitMsg { game, select, playerColor, ready } =
    let
        { europe, asia, africa, northAmerica, southAmerica } =
            game.unitBoard

        drawUnits : Continent -> Maybe Unit -> Maybe Move -> List ( ( Float, Float ), Image Msg )
        drawUnits continent maybeUnit maybeMove =
            case maybeUnit of
                Just ({ color } as unit) ->
                    case maybeMove of
                        Just ({ direction } as move) ->
                            let
                                amount =
                                    unit.amount - move.amount
                            in
                            [ { amount = amount, color = color }
                                |> UnitView.drawCenter
                                    continent
                                    { used = True }
                                    (BoardSpecific << OpenSelectGui)
                                    playerColor
                            , { amount = move.amount, color = color }
                                |> UnitView.draw
                                    direction
                                    continent
                            ]

                        Nothing ->
                            [ unit
                                |> UnitView.drawCenter
                                    continent
                                    { used =
                                        unit.amount
                                            <= 1
                                            || (playerColor /= color)
                                            || ready
                                            || (game.state /= Running)
                                    }
                                    (BoardSpecific << OpenSelectGui)
                                    playerColor
                            ]

                Nothing ->
                    []
    in
    List.concat
        [ Continent.list
            |> List.map
                (\continent ->
                    game.unitBoard
                        |> Board.get continent
                        |> drawCard continent
                )
            |> List.filterMap identity
        , Continent.list
            |> List.map
                (\continent ->
                    let
                        maybeMove =
                            game.moveBoard
                                |> Board.get continent

                        maybeUnit =
                            game.unitBoard
                                |> Board.get continent
                    in
                    maybeMove
                        |> drawUnits continent maybeUnit
                )
            |> List.concat
        , case select of
            Nothing ->
                []

            Just ( continent, selectGui ) ->
                drawSelectGui continent selectGui
        , [ ( ( View.tileSize * 3, View.tileSize * 4 )
            , case game.state of
                Win _ ->
                    Card.exit
                        |> Image.withAttributes [ Image.onClick <| ServerSpecific Reset ]

                Draw ->
                    Card.exit
                        |> Image.withAttributes [ Image.onClick <| ServerSpecific Reset ]

                _ ->
                    if ready then
                        Card.watch

                    else
                        Card.submit
                            |> Image.withAttributes [ Image.onClick submitMsg ]
            )
          ]
        ]


view : State -> { title : String, options : Options Msg, body : List (Area Msg) }
view state =
    let
        size : Float
        size =
            View.tileSize * 8

        background : Background
        background =
            Graphics.imageBackground
                { height = size
                , width = size
                , source = "background.png"
                }

        body : List (Area Msg)
        body =
            [ Graphics.imageArea
                { height = size
                , background = background
                }
                (case state of
                    Client model ->
                        model |> drawModel (ClientSpecific Ready)

                    Host ( model, _ ) ->
                        model |> drawModel (HostSpecific Submit)

                    WaitingHost _ ->
                        TitleScreenView.waiting

                    Guest _ ->
                        TitleScreenView.normal (GuestSpecific <| Response FindOpenGame)

                    FetchingTime ->
                        TitleScreenView.normal None
                )
            ]
    in
    { title = "Mini World War"
    , options = Graphics.options { width = size, transitionSpeedInSec = 0.012 }
    , body = body
    }



{------------------------
   MAIN
------------------------}


main : PixelEngine () State Msg
main =
    game
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , controls = controls
        }
