module MiniWorldWar.Role.Host exposing (TransitionData, initHost, tick, update)

import Action
import MiniWorldWar.Data.Color exposing (Color(..))
import MiniWorldWar.Data.Game as Game exposing (Game, GameState(..))
import MiniWorldWar.Request exposing (Response(..))
import MiniWorldWar.Request.Host as HostRequest exposing (Msg(..))
import MiniWorldWar.Role exposing (HostModel)
import MiniWorldWar.View.GameScreen as GameScreenView
import Random exposing (Seed)
import Time exposing (Posix)


type alias TransitionData =
    { game : Game
    , seed : Seed
    , time : Posix
    , id : String
    }


initHost : TransitionData -> ( HostModel, Cmd (Response Msg) )
initHost { game, seed, time, id } =
    let
        ( newGame, newSeed ) =
            seed
                |> Random.step
                    (game |> Game.nextRound time)
    in
    ( ( { time = time
        , id = id
        , game = newGame
        , select = Nothing
        , playerColor = Red
        , ready = False
        , error = Nothing
        }
      , newSeed
      )
    , newGame
        |> HostRequest.submit id
    )


type alias Action =
    Action.Action HostModel (Response Msg) Never Never


tick : HostModel -> Posix -> Action
tick ( { ready, id, game } as model, seed ) time =
    let
        { lastUpdated } =
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
                Action.updating
                    ( ( { model
                            | game = newGame
                            , time = time
                            , ready = False
                        }
                      , newSeed
                      )
                    , HostRequest.submit id newGame
                    )

            _ ->
                Action.updating
                    ( ( { model | time = time }, seed )
                    , HostRequest.waitingForClient id lastUpdated
                    )

    else
        Action.updating
            ( ( { model | time = time }, seed ), Cmd.none )


update : Msg -> HostModel -> Action
update msg (( { game, id, time, ready } as model, seed ) as modelAndSeed) =
    case msg of
        Submit ->
            let
                newGame =
                    { game
                        | lastUpdated = time |> Time.posixToMillis
                        , state = HostReady
                    }
            in
            Action.updating
                ( ( { model
                        | ready = True
                        , game = newGame
                    }
                  , seed
                  )
                , HostRequest.submit id newGame
                )

        UpdateMoveBoard moveBoard ->
            Action.updating
                ( ( { model
                        | game =
                            game
                                |> Game.addMoveBoard moveBoard
                                |> (\g -> { g | state = BothReady })
                    }
                  , seed
                  )
                , Cmd.none
                )

        WaitingForClient ->
            Action.updating
                ( modelAndSeed
                , HostRequest.waitingForClient id game.lastUpdated
                )

        UISpecific uiMsg ->
            if ready then
                Action.updating
                    ( ( model, seed ), Cmd.none )

            else
                Action.updating
                    ( ( GameScreenView.update uiMsg model, seed ), Cmd.none )
