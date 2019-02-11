module MiniWorldWar.View.Card exposing (watch,card,submit,exit)

import PixelEngine.Graphics.Image as Image exposing (Image, image)
import PixelEngine.Graphics.Tile exposing (Tile, tile, Tileset)
import MiniWorldWar.Data.Color as Color exposing (Color(..))
import MiniWorldWar.Data.Continent as Continent exposing (Continent(..))

tileset : Tileset
tileset = 
  { source = "cards.png"
  , spriteWidth = 16*2
  , spriteHeight = 16*3
  }

card : Continent -> Color -> Image msg
card continent color =
  Image.fromTile
    (tile
      ( Continent.toInt continent
      , color |> Color.toInt
      )
    )
    tileset

watch : Image msg
watch =
  image "watch.png"

submit : Image msg
submit =
  image "submit.png"

exit : Image msg
exit =
  image "exit.png"