# Pronicula
This is a collection of various graphics experiments. Mostly gdshader code along with some gdscript.
The core idea behind all of these experiments is to try to put as much of the logic as possible into the shader code and ideally
have the CPU do nothing outside providing the engine environment. Thereby, problems that would be solved through basic state machines on the CPU
become interesting logic puzzles on the GPU. "How could one implement this without access to the state of prior iterations or the state of neighbors?"

An additional quirk of the shader focused approach is that most of these demos can be displayed fully in editing-mode in Godot, never needing the "game" to be run.
It also means that, for web export, web GPU can be utilized instead of the comparatively slow (specifically for large numbers of entities and logic loops) gdscript.

However, not all demos utilize the GPU to the same extent. Some are completely single-shader-based (see [Hamsters](#hamsters)), some make use of multiple shaders working together (see [Trains](#trains)), and some actually leave some stateful logic to the CPU (see [Switching Tiles](#switching-tiles)).

#### Controls
All of these demos can be controlled the same way:
1. **Mouse + keyboard**
    - Use the scroll wheel to zoom in or out (infinitely).
    - Press and hold the scroll wheel and drag the mouse to move the screen around.
    - Use right click (+ drag) and keyboard input on the Godot-GUI elements included in the demos.
2. **Touchscreen**
    - Use two-finger-dragging to zoom in our out (infinitely).
    - Use one-finger-dragging to move the screen around.
    - Use taps and dragging (+ on-screen-keyboard) as input on the Godot-GUI elements included in the demos.

If additional controls exist for a specific demo, then they are explained in the corresponding section.

## Hamsters
In a completely stateless manner, this shader renders hamsters walking around, running on wheels, and getting flung by them.
Except for cosmetic parameters that stay static, the entire animation is an analytical function of time. This means it can be
played forward and backward all from within the editor view without running the scene.

The downside of this approach is that every fragment loops over all hamsters to see if it needs to render them.
This means performance scales poorly with high hamster counts and resolutions. However, if the hamsters were drawn with a [Splesh](#splesh) approach, while performance would no longer suffer, the in-editor rendering for arbitrary hamster counts would also no longer work. This is because dynamic meshes would need to be generated depending on how many hamsters need to be rendered and a normal ColorRect would no longer be viable.

TODO: More thorough explanation

## Splesh
By generating a mesh made up of *x* disjoint quads, *x* different entities with their own UV space and varying coordinates can be
rendered extremely efficiently in a single drawcall and without per-pixel looping over entities.
This is because the fragment shader receives the index of the quad from the vertex shader and can therefore immediately focus on rendering
without needing to loop over entities to find out which one it belongs to.

My system was able to render 30 million moving "entities" with smooth 60FPS, the real bottleneck beyond this point being generating and storing the giant mesh of quads.

TODO: More thorough explanation

## Trains
The train demo renders an infinitely scalable map covered in train tracks across which trains made up of a dynamically scalable amounts of cars/segments travel.
For this, the demo is made up of two separate shaders (both making use of [train_tracks.gdshaderinc](/shaders/demos/trains/train_tracks.gdshaderinc) for shared logic):
1. **The background shader** ([trains_background.gdshader](/shaders/demos/trains/trains_background.gdshader)):
   - Renders the train tracks and track joints on a 2D color rect.
2. **The train shader** ([trains_splesh.gdshader](/shaders/demos/trains/trains_splesh.gdshader)):
   - Uses the vertex shader to place every quad of a splesh at a specific position in space to represent a single train car/segment.
   - Uses the fragment shader to give single trains the same color across every segment.

The shader code translates between various coordinate systems depending on the situation:
- **UV space**: The base coordinates of the fragments background shader.
- **WORLD space**: The main coordinate system of the background shader. (```UV * global_size```)
- **JITTER GROUP space**: WORLD space is divided into a larger grid in which every fragment in the same jitter group is jittered the same way.
  Every jitter group contains exactly one track joint at its center. Because the groups themselves jitter differently, this allows for a random looking distribution of joints. (```WORLD / JITTER_BOUNDS```)
- **CIRCUIT space**: JITTER GROUP space is further divided into areas of multiple joints which all always contain a complete circuit. These circuits are picked from a premade selection of circuits and then bridged together. This is done because fully random connections on their own do not have high enough connectivity for good train movement. (```JITTER GROUP / CIRCUIT_SIZE```)
- **VERTEX space**: Coordinates relative to the geometry of the splesh. The position of a train segment needs to be calculated in JITTER GROUP space first to know which joints it has been moving along and then translated into VERTEX space as the output of the vertex shader. (```JITTER GROUP * JITTER_BOUNDS / global_size```)

As mentioned earlier, the background shader first lays out the joints in a grid, then connects them as a set of disjoint circuits, then bridges these circuits randomly, and finally jitters
the track joints for a random looking network. The train shader has trains spawn on random joints at random times and then iteratively calculates their movement over their lifetime (which is a modifiable parameter) up to the iteration of the current time uniform. Since the trains are only on the GPU and no state is ever written, this iterative process needs to be calculated again every frame. However, since it only needs to be done on the vertex level and is fully parallelizable between vertices on the GPU, it is very fast. To choose which tracks to take at each iteration, the train shader makes use of the same logic as the background shader, being able to move to one of:
- **A**: The previous joint in a circuit (if the current joint is part of a circuit)
- **B**: The next joint in a circuit (if the current joint is part of a circuit)
- **D**: The joint that the outgoing bridge (every joint has one) of the current joint is connected to
- **E**: One of the four neighbor joints in the grid (*only if* there exists an incoming bridge from them to the current joint)

While the choice which joint to move to next is random, a choice that would result in the train backtracking to the joint it was at previously is always skipped (unless its the only possible option) to make movement seem more natural.


#### GUI Parameters
The GUI offers a few parameters for experimenting with the demo code.
- **Time speed**: The speed at which the uniform time parameter changes. Since the demo is stateless, this speed can also be negative to reverse time.
- **Size**: The world size. Larger size means more train tracks.
- **Train size factor**: Scales the size of the trains in relation to the world size.
- **Seed**: All pseudo-randomness is based on this seed.
- **Track jitter**: Controls the intensity with which the train track joints are offset to produce less grid-like layouts.
- **Show jitter**: Displays a checker pattern which visualizes how the jitter works.
- **Splesh quads count**: Changing this generates a new [splesh](#splesh) with the given amount of quads. Defines the amount of train segments.
- **Train length**: Defines how many cars/segments make up a single train.
- **Train lifetime**: Defines how many steps between track joints the trains are alive for before they respawn somewhere else.
- **Train greyness**: Allows changing the saturation of the train colors.


## Switching Tiles
A grid of tiles where two tiles periodically switch places.

This shader and script were the first experiment with how well I could partially offload a stateful animation to the shader.
State switches are handled by the script while rendering and animation is handled by the shader.

TODO: More thorough explanation? Maybe there is not much more to be said