module Main exposing (main)

import Dom
import Html exposing (Html, Attribute, div, textarea, button)
import Html.Attributes exposing
  (style, id, value, disabled, property, attribute)
import Html.Events exposing (onInput, onClick, on)
import Html.Keyed as Keyed
import Json.Encode
import Json.Decode exposing (Decoder)
import Process
import Task
import Time

main : Program Never Model Msg
main =
  Html.program
    { init = init
    , update = update
    , subscriptions = always Sub.none
    , view = view
    }

type alias Model =
  { frame : Frame
  , edits : List Edit
  , editCount : Int
  , futureEdits : List Edit
  , inputCount : Int
  }

type alias Edit =
  { before : Frame
  , after : Frame
  }

type alias Frame =
  { text : String
  , start : Int
  , stop : Int
  }

init : ( Model, Cmd Msg )
init =
  ( { frame =
        let text = "hello" in
          { text = text
          , start = String.length text
          , stop = String.length text
          }
    , edits = []
    , editCount = 0
    , futureEdits = []
    , inputCount = 0
    }
  , Cmd.none
  )

type Msg
  = NoOp
  | TextChanged (Int, String)
  | Replace (Int, Int, String)
  | Undo (Int, Int)
  | Redo (Int, Int)
  | KeyDown (Int, String, Int)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NoOp ->
      ( model, Cmd.none )
    TextChanged (editCount, text) ->
      ( if editCount /= model.editCount || text == model.frame.text then
          model
        else
          let frame = model.frame in
            { model
            | frame = { frame | text = text }
            , inputCount = model.inputCount + 1
            }
      , Cmd.none
      )
    Replace ( start, stop, replacement ) ->
      ( let
          after =
            { text =
                String.concat
                  [ String.left start model.frame.text
                  , replacement
                  , String.dropLeft stop model.frame.text
                  ]
            , start = start + String.length replacement
            , stop = start + String.length replacement
            }
        in
          { model
          | frame = after
          , edits =
              { before =
                  { text = model.frame.text
                  , start = start
                  , stop = stop
                  }
              , after = after
              } ::
                model.edits
          , editCount = model.editCount + 1
          , futureEdits = []
          }
      , Task.attempt (always NoOp) (Dom.focus "catcher")
      )
    Undo ( editCount, inputCount ) ->
      case model.edits of
        [] ->
          ( model, Cmd.none )
        edit :: edits ->
          if
            editCount == model.editCount &&
              inputCount == model.inputCount &&
                model.frame.text == edit.after.text
          then
            ( { model
              | frame = edit.before
              , edits = edits
              , editCount = model.editCount - 1
              , futureEdits = edit :: model.futureEdits
              }
            , Task.attempt (always NoOp) (Dom.focus "catcher")
            )
          else
            ( model, Cmd.none )
    Redo ( editCount, inputCount ) ->
      case model.futureEdits of
        [] ->
          ( model, Cmd.none )
        edit :: futureEdits ->
          if
            editCount == model.editCount &&
              inputCount == model.inputCount &&
                model.frame.text == edit.before.text
          then
            ( { model
              | frame = edit.after
              , edits = edit :: model.edits
              , editCount = model.editCount + 1
              , futureEdits = futureEdits
              }
            , Task.attempt (always NoOp) (Dom.focus "catcher")
            )
          else
            ( model, Cmd.none )
    KeyDown (editCount, "c", 90) ->
      ( model
      , Task.perform
          (always (Undo (editCount, model.inputCount)))
          (Process.sleep (50 * Time.millisecond))
      )
    KeyDown (editCount, "cs", 90) ->
      ( model
      , Task.perform
          (always (Redo (editCount, model.inputCount)))
          (Process.sleep (50 * Time.millisecond))
      )
    KeyDown (editCount, "c", 89) ->
      ( model
      , Task.perform
          (always (Redo (editCount, model.inputCount)))
          (Process.sleep (50 * Time.millisecond))
      )
    KeyDown x ->
      ( model, Cmd.none )

view : Model -> Html Msg
view model =
  div
    []
    [ Keyed.node
        "div"
        [ style
            [ ( "width", "500px" )
            , ( "height", "200px" )
            , ( "position", "relative" )
            ]
        ]
        ( List.concat
            [ List.map2
                (viewHiddenFrame cancelUndo)
                ( List.range
                    (model.editCount - List.length model.edits)
                    (model.editCount - 1)
                )
                (List.map .before (List.reverse model.edits))
            , [ viewFrame model.editCount model.frame ]
            , List.map2
                (viewHiddenFrame cancelRedo)
                ( List.range
                    (model.editCount + 1)
                    (model.editCount + List.length model.futureEdits)
                )
                (List.map .after model.futureEdits)
            ]
        )
    , button
        [ onClick (Replace ( 1, 2, "ea" ))
        ]
        [ Html.text "e -> ea"
        ]
    , button
        [ onClick (Undo (model.editCount, model.inputCount))
        , disabled (not (canUndo model))
        ]
        [ Html.text "Undo"
        ]
    , button
        [ onClick (Redo (model.editCount, model.inputCount))
        , disabled (not (canRedo model))
        ]
        [ Html.text "Redo"
        ]
    , Html.text (toString model)
    ]

viewFrame : Int -> Frame -> (String, Html Msg)
viewFrame i frame =
  ( toString i
  , textarea
      [ onInput (TextChanged << (,) i)
      , on "keydown" (Json.Decode.map KeyDown (decodeKeyEvent i))
      , value frame.text
      , id "catcher"
      , property
          "selectionStart"
          (Json.Encode.int frame.start)
      , property
          "selectionEnd"
          (Json.Encode.int frame.stop)
      , style
          [ ( "width", "100%" )
          , ( "height", "100%" )
          , ( "position", "absolute" )
          , ( "top", "0px" )
          , ( "left", "0px" )
          , ( "box-sizing", "border-box" )
          , ( "margin", "0px" )
          ]
      ]
      []
  )

viewHiddenFrame : String -> Int -> Frame -> (String, Html Msg)
viewHiddenFrame inputScript i frame =
  ( toString i
  , textarea
      [ value frame.text
      , attribute "oninput" inputScript
      , style
          [ ( "width", "100%" )
          , ( "height", "25%" )
          , ( "position", "absolute" )
          , ( "bottom", "0px" )
          , ( "left", "0px" )
          , ( "box-sizing", "border-box" )
          , ( "margin", "0px" )
          , ( "visibility", "hidden" )
          ]
      ]
      []
  )

cancelUndo : String
cancelUndo =
  "document.execCommand(\"redo\", true, null)"

cancelRedo : String
cancelRedo =
  "document.execCommand(\"undo\", true, null)"

canUndo : Model -> Bool
canUndo model =
  case model.edits of
    [] -> False
    edit :: _ -> model.frame.text == edit.after.text

canRedo : Model -> Bool
canRedo model =
  case model.futureEdits of
    [] -> False
    edit :: _ -> model.frame.text == edit.before.text

decodeKeyEvent : Int -> Json.Decode.Decoder (Int, String, Int)
decodeKeyEvent editCount =
  Json.Decode.map2
    ((,,) editCount)
    ( Json.Decode.map4
        concat4Strings
        (ifFieldThenString "ctrlKey" "c")
        (ifFieldThenString "metaKey" "c")
        (ifFieldThenString "altKey" "a")
        (ifFieldThenString "shiftKey" "s")
    )
    (Json.Decode.field "which" Json.Decode.int)

concat4Strings : String -> String -> String -> String -> String
concat4Strings x y z w =
  x ++ y ++ z ++ w

ifFieldThenString : String -> String -> Json.Decode.Decoder String
ifFieldThenString field s =
  Json.Decode.map (stringIfTrue s) (Json.Decode.field field Json.Decode.bool)

stringIfTrue : String -> Bool -> String
stringIfTrue s true =
  if true then s else ""
