# Pronicula
This is a collection of various graphics experiments. Mostly gdshader code along with some gdscript.

## Hamsters
This shader renders hamsters walking around, running on wheels, and getting flung by them all without state.
With the exception of cosmetic parameters that stay static, the entire animation is an analytical function of time.

## Splesh
By generating a mesh made up of x disjoint quads, x different entities with their own UV space and varying coordinates can be
rendered extremely efficiently in a single drawcall and without per-pixel looping over entities.
This is because the fragment shader receives the index of the quad from the vertex shader and can therefore immediately focus on rendering
without needing to loop over entities to find out which one it belongs to.

## Switching Tiles
This shader and script were the first experiment with how well I could partially offload a stateful animation to the shader.
State switches are handled by the script while rendering and animation is handled by the shader.
