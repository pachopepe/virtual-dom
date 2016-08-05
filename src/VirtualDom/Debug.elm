module VirtualDom.Debug exposing (program)
{-|
@docs program
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Native.Debug
import Native.VirtualDom
import Task
import VirtualDom as VDom exposing (Node)
import VirtualDom.Expando as Expando exposing (Expando)
import VirtualDom.History as History exposing (History)



-- PROGRAMS


{-|-}
program
  : { init : (model, Cmd msg)
    , update : msg -> model -> (model, Cmd msg)
    , subscriptions : model -> Sub msg
    , view : model -> Node msg
    }
  -> Program Never (Model model msg) (Msg msg)
program { init, update, subscriptions, view } =
  Native.VirtualDom.debug
    { init = wrapInit init
    , view = wrapView view
    , update = wrapUpdate update
    , viewIn = viewIn
    , viewOut = viewOut
    , subscriptions = wrapSubs subscriptions
    }



-- MODEL


type alias Model model msg =
  { history : History model msg
  , state : State model
  , expando : Expando
  }


type State model
  = Running model
  | Paused Int model model


wrapInit : ( model, Cmd msg ) -> ( Model model msg, Cmd (Msg msg) )
wrapInit ( userModel, userCommands ) =
  { history = History.empty userModel
  , state = Running userModel
  , expando = Expando.init userModel
  }
    ! [ Cmd.map UserMsg userCommands ]



-- UPDATE


type Msg msg
  = NoOp
  | UserMsg msg
  | ExpandoMsg Expando.Msg
  | Play
  | Jump Int


wrapUpdate
  : (msg -> model -> (model, Cmd msg))
  -> Msg msg
  -> Model model msg
  -> (Model model msg, Cmd (Msg msg))
wrapUpdate userUpdate msg model =
  case msg of
    NoOp ->
      model ! []

    UserMsg userMsg ->
      updateUserMsg userUpdate userMsg model

    ExpandoMsg eMsg ->
      { model | expando = Expando.update eMsg model.expando }
        ! []

    Play ->
      case model.state of
        Running _ ->
          model ! []

        Paused _ _ userModel ->
          { history = model.history
          , state = Running userModel
          , expando = Expando.merge userModel model.expando
          }
            ! [ scrollMessages ]

    Jump index ->
      let
        (indexModel, indexMsg) =
          History.get userUpdate index model.history
      in
        { history = model.history
        , state = Paused index indexModel (getLatestModel model.state)
        , expando = Expando.merge indexModel model.expando
        }
          ! []



-- UPDATE - USER MESSAGES


updateUserMsg
  : (msg -> model -> (model, Cmd msg))
  -> msg
  -> Model model msg
  -> (Model model msg, Cmd (Msg msg))
updateUserMsg userUpdate userMsg { history, state, expando } =
  let
    userModel =
      getLatestModel state

    newHistory =
      History.add userMsg userModel history

    (newUserModel, userCmds) =
      userUpdate userMsg userModel

    commands =
      Cmd.map UserMsg userCmds
  in
    case state of
      Running _ ->
        { history = newHistory
        , state = Running newUserModel
        , expando = Expando.merge newUserModel expando
        }
          ! [ commands, scrollMessages ]

      Paused index indexModel _ ->
        { history = newHistory
        , state = Paused index indexModel newUserModel
        , expando = expando
        }
          ! [ commands ]


scrollMessages : Cmd (Msg msg)
scrollMessages =
  Cmd.none -- TODO


getLatestModel : State model -> model
getLatestModel state =
  case state of
    Running model ->
      model

    Paused _ _ model ->
      model



-- SUBSCRIPTIONS


wrapSubs : (model -> Sub msg) -> Model model msg -> Sub (Msg msg)
wrapSubs userSubscriptions {state} =
  getLatestModel state
    |> userSubscriptions
    |> Sub.map UserMsg



-- VIEW


wrapView : (model -> Node msg) -> Model model msg -> Node (Msg msg)
wrapView userView { state } =
  getLatestModel state
    |> userView
    |> VDom.map UserMsg



-- SMALL DEBUG VIEW


viewIn : Model model msg -> Node ()
viewIn { history } =
  div
    [ VDom.on "click" (Decode.succeed ())
    , VDom.style
        [ ("width", "40px")
        , ("height", "40px")
        , ("borderRadius", "50%")
        , ("position", "absolute")
        , ("bottom", "0")
        , ("right", "0")
        , ("margin", "10px")
        , ("backgroundColor", "#60B5CC")
        , ("color", "white")
        , ("display", "flex")
        , ("justify-content", "center")
        , ("align-items", "center")
        ]
    ]
    [ VDom.text (toString (History.size history))
    ]



-- BIG DEBUG VIEW


viewOut : Model model msg -> Node (Msg msg)
viewOut { history, state, expando } =
    div
      [ VDom.attribute "id" "debugger" ]
      [ styles
      , viewMessages state history
      , VDom.map ExpandoMsg <|
          div [ VDom.attribute "id" "values" ] [ Expando.view Nothing expando ]
      ]


viewMessages state history =
  case state of
    Running _ ->
      div [ class "debugger-sidebar" ]
        [ VDom.map Jump (History.view Nothing history)
        ]

    Paused index _ _ ->
      div [ class "debugger-sidebar" ]
        [ VDom.map Jump (History.view (Just index) history)
        , div
            [ class "debugger-sidebar-play"
            , VDom.on "click" (Decode.succeed Play)
            ]
            [ VDom.text "Play" ]
        ]


div =
  VDom.node "div"


id =
  VDom.attribute "id"


class name =
  VDom.property "className" (Encode.string name)


-- STYLE


styles : Node msg
styles =
  VDom.node "style" [] [ VDom.text """

html {
    overflow: hidden;
    height: 100%;
}

body {
    height: 100%;
    overflow: auto;
}

#debugger {
  display: flex;
  font-family: monospace;
  height: 100%;
}

#values {
  height: 100%;
  width: 100%;
  margin: 0;
  overflow: scroll;
  cursor: default;
}

.debugger-sidebar {
  background-color: rgb(61, 61, 61);
  height: 100%;
  width: 300px;
  display: flex;
  flex-direction: column;
}

.debugger-sidebar-play {
  background-color: rgb(50, 50, 50);
  width: 300px;
  cursor: pointer;
  color: white;
  padding: 8px 0;
  text-align: center;
}

.debugger-sidebar-messages {
  width: 300px;
  overflow-y: scroll;
  flex: 1;
}

.messages-entry {
  cursor: pointer;
  color: white;
  padding: 4px 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
  overflow: hidden;
}

.messages-entry:hover {
  background-color: rgb(41, 41, 41);
}

.messages-entry-selected, .messages-entry-selected:hover {
  background-color: rgb(10, 10, 10);
}
""" ]