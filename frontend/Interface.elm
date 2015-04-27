-- Interface.elm
-- This defines and renders an interactive interface for editing the
-- program and output of the language as defined in int-trees.

--Import the language and its parsing utilities
--import Lang
--import LangParser
--import Sync
--import Utils

import List exposing (..)
import Dict exposing (..)
import String exposing (..)
import Graphics.Element as GE exposing (..)
import Graphics.Collage as GC exposing (..)
import Result exposing (..)
import Signal exposing (..)

import Mouse exposing (..)
import Window exposing (..)
import Html exposing (..)
import Html.Attributes as Attr exposing (..) 
import Html.Events as Events exposing (..) 

import Svg
import Svg.Attributes
import Svg.Events
import Svg.Lazy

-- Model --
--code is the text from the codebox
--output: the parsed representation
--of the code (this type will change later)
--objects: a list of the objects
--selected: the possible key of a selected object
type alias Model = { code : String
                    , output : List (List Int) --temporary
                    , objects : List Object
                    , selected : Maybe (List Int)
                    , movingObj : Maybe (Object, Float, Float)
                   }

type alias Object = (Svg.Svg, Int, Int)

initModel = { code = ""
            , output = []
            , objects = []
            , selected = Nothing
            , movingObj = Nothing
            }

sampleModel = { code = "[[50,100],[150,100],[250,100]]"
            , output = [[50,100],[150,100],[250,100]] 
            , objects = List.map (\(f,x,y) -> (GC.toForm f,x,y))
                        <| List.map (\(l,w,z) -> (Html.toElement 50 50 l,w,z))
                        <| justList
                        <| List.map (\s -> buildSquare s) 
                            [[50,100],[150,100],[250,100]]
            , selected = Nothing
            , movingObj = Nothing
            }

type Event = CodeUpdate String
           | OutputUpdate String
           | SelectObject (List Int)
           | MouseDown (Int, Int)
           | MouseUp

events : Signal.Mailbox Event
events = Signal.mailbox <| CodeUpdate ""

-- Update --
upstate : Event -> Model -> Model
upstate evt old = case evt of
    CodeUpdate newcode -> { old | code <- newcode }
    MouseUp            -> { old | movingObj <- Nothing }
    MouseDown (mx, my) -> case old.movingObj of
        Nothing                 ->
            let maybeObj = pickObj (mx, my) (old.objects)
            in case maybeObj of
                Nothing -> old
                Just (form, x, y) -> { old | movingObj <- Just ((form, x, y)
                                                                 , form.x -
                                                                    Basics.toFloat mx
                                                                 , form.y -
                                                                    Basics.toFloat my
                                                                 )
                                     }
        Just (obj, xdist, ydist) ->
            let newpos = (Basics.toFloat mx + xdist, Basics.toFloat my + ydist)
                newobjs = List.map (updateObjPos newpos obj)
                                    old.objects
            in  { old | objects <- newobjs 
                        , movingObj <- Just 
                            (updateObjPos newpos obj obj, xdist, ydist)
                }
    _ -> old


pickObj : (Int, Int) -> List Object -> Maybe Object
pickObj (mx, my) objs = case objs of
    [] -> Nothing
    (form, x, y) :: xs -> if | abs (form.x - Basics.toFloat mx) <= 20 
                               && abs (form.y - Basics.toFloat my) <= 20 -> Just (form, x, y)
                             | otherwise -> pickObj (mx, my) xs

updateObjPos : (Float, Float) -> Object -> Object -> Object
updateObjPos (newx, newy) obj other = if
    | obj == other -> let (form, xpos, ypos) = obj
                      in ({ form | x <- newx, y <- newy }, xpos, ypos)
    | otherwise -> other

mouseUp : Bool -> (Bool, Maybe Event) -> (Bool, Maybe Event)
mouseUp newevt (oldevt, _) = case (oldevt, newevt) of
    (True, False) -> (newevt, Just MouseUp)
    _             -> (newevt, Nothing)


adjustCoords : (Int, Int) -> (Int, Int) -> (Int, Int)
adjustCoords (w,h) (mx, my) = (mx - 3 * (w // 4), (-1 * my) + h // 2)

-- View --
codeBox : String -> Html.Html
codeBox codeText =
    Html.textarea
        [ Attr.id "codeBox"
        , Attr.style
            [ ("height", "100%")
            , ("width",  "100%")
            , ("resize", "none")
            , ("overflow", "scroll")
            ]
        , Attr.value codeText
        , Events.on "input" Events.targetValue
            (Signal.message events.address << CodeUpdate)
        ]
        []

visualsBox : Model -> Float -> Html.Html
visualsBox model dim =
    let
        intdim = floor (dim/20)
    in 
        Svg.svg <| List.map (\(f,x,y) -> f) model.objects 

buildSquare : List Int -> Maybe (Svg.Svg, Int, Int)
buildSquare coords =
    case coords of
        [x,y] -> 
                Just (Svg.rect
                    [ Svg.Attribtes.cx "x" --TODO int to str
                    , Svg.Attributes.cy "y" --TODO int to str
                    , Svg.Attributes.width "60"
                    , Svg.Attributes.height "60"
                    , Svg.Events.onMouseDown (Signal.message events.address
                        (SelectObject coords)) --TODO id of some sort
                    , Svg.Events.onMouseUp (Signal.message events.address
                        (DeselectObject coords)) --TODO Add this type
                    , Svg.Events.onMouseOut (Signal.message events.address
                        (DeselectObject coords)) --TODO Add this type
                    ]
                    []
                , x --TODO no longer needed
                , y --TODO no longer needed
                )
        _     -> Nothing

justList : List (Maybe (Html.Html, Int, Int)) -> List (Html.Html, Int, Int)
justList l = 
    case l of
        Just v :: vs  -> v :: (justList vs)
        Nothing :: vs -> justList vs
        _             -> []


view : (Int, Int) -> Model -> Html.Html
view (w,h) model = 
    let
        dim = (Basics.toFloat (Basics.min w h)) / 2
    in
        Html.div
            [ Attr.style
                [ ("width", w)
                , ("height", h)
                ]
            ]
            [ Html.div 
                [ Attr.style
                    [ ("width", w // 2) 
                    , ("height", h)
                    ]
                ]
                [codeBox model.code]
            , Html.div
                [ Attr.style
                    [ ("width", w // 2)
                    , ("height", h)
                    ]
                ]    
                [visualsBox model dim]
            ]
            
                    
                                    



-- Main --
main : Signal Html.Html
main = let sigModel = Signal.foldp upstate sampleModel
                        <| Signal.mergeMany
                            [ events.signal
                            , Signal.map (\(a,Just x) -> x)
                                            <| Signal.filter (\(a,x) -> x /= Nothing)
                                                             (False, Just
                                                                     MouseUp)
                                            <| Signal.foldp mouseUp 
                                                            (False, Nothing)
                                                            Mouse.isDown 
                                        , Signal.map MouseDown
                                            <| Signal.map2 adjustCoords
                                                           Window.dimensions
                                            <| (Signal.sampleOn Mouse.isDown
                                                                  Mouse.position)
                            ]
       in Signal.map2 view Window.dimensions sigModel
