# Pronicula
This is a collection of various graphics experiments. Mostly gdshader code along with some gdscript.

## Hamsters
In a completely stateless manner, this shader renders hamsters walking around, running on wheels, and getting flung by them.
Except for cosmetic parameters that stay static, the entire animation is an analytical function of time. This means it can be
played forward and backward all from within the editor view without running the scene.

The downside of this approach is that every fragment loops over all hamsters to see if it needs to render them.
This means performance scales poorly with high hamster counts and resolutions. However, if the hamsters were drawn with a [Splesh](#splesh) approach, while performance would no longer suffer, the in-editor rendering for arbitrary hamster counts would also no longer work. This is because dynamic meshes would need to be generated depending on how many hamsters need to be rendered and a normal ColorRect would no longer be viable.

## Splesh
By generating a mesh made up of *x* disjoint quads, *x* different entities with their own UV space and varying coordinates can be
rendered extremely efficiently in a single drawcall and without per-pixel looping over entities.
This is because the fragment shader receives the index of the quad from the vertex shader and can therefore immediately focus on rendering
without needing to loop over entities to find out which one it belongs to.

My system was able to render 30 million moving "entities" with smooth 60FPS, the real bottleneck beyond this point being generating and storing the giant mesh of quads.

## Switching Tiles
A grid of tiles where two tiles periodically switch places.

This shader and script were the first experiment with how well I could partially offload a stateful animation to the shader.
State switches are handled by the script while rendering and animation is handled by the shader.
