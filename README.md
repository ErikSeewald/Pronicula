# Pronicula
This is a collection of various graphics experiments. Mostly gdshader code along with some gdscript.
The core idea behind all of these experiments is to try to put as much of the logic as possible into the shader code and ideally
have the CPU do nothing outside providing the engine environment. Thereby, problems that would be solved through basic state machines on the CPU
become interesting logic puzzles on the GPU. "How could one implement this without access to the state of prior iterations or the state of neighbors?"

An additional quirk of the shader focused approach is that most of these demos can be displayed fully in editing-mode in Godot, never needing the "game" to be run.
It also means that, for web export, web GPU can be utilized instead of the comparatively slow (specifically for large numbers of entities and logic loops) gdscript.

However, not all demos utilize the GPU to the same extent. Some are completely single-shader-based (see [Hamsters](#hamsters), [Grid Machine](#grid-machine)), some make use of multiple shaders working together (see [Trains](#trains)), and some actually leave some stateful logic to the CPU (see [Switching Tiles](#switching-tiles)).

To start any of the demos, run the [/scenes/menu/menu.tscn](/scenes/menu/menu.tscn) scene in godot.

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
The zooming and dragging logic is implemented in the [pronicula_nodes](/addons/pronicula_nodes/) addon provided with this repo.

#### Project structure
- [addons](/addons/) contains utility code for deploying the shader demos.
- [assets](/assets/) contain a small set of static assets such as the GUI theme and pre-generated [splesh](#splesh) meshes for testing.
- [scenes](/scenes/), [scripts](/scripts/), and [shaders](/shaders/) are each structured the same but for the corresponding file types.
  - **demos**: Directory containing subdirectories for files belong to a specific demo
  - **util**: Directory for utility files
  - ...
  - -> Files in *x*/*a* and *y*/*a* belong to each other semantically but are of a different file type.

## Hamsters
In a completely stateless manner, this shader renders hamsters walking around, running on wheels, and getting flung by them.
Except for cosmetic parameters that stay static, the entire animation is an analytical function of time. This means it can be
played forward and backward all from within the editor view without running the scene.

The downside of this approach is that every fragment loops over all hamsters to see if it needs to render them.
This means performance scales poorly with high hamster counts and resolutions. However, if the hamsters were drawn with a [Splesh](#splesh) approach, while performance would no longer suffer, the in-editor rendering for arbitrary hamster counts would also no longer work. This is because dynamic meshes would need to be generated depending on how many hamsters need to be rendered and a normal ColorRect would no longer be viable.

The fragment shader is divided into two phases. First, it checks all hamsters and draws them if they overlap the fragment.
Then it passes some information calculated during the hamster phase to the second phase, where the wheels are drawn.
1. **The hamster phase**
   - A loop over all hamsters as defined by *hamster_count*
   - Each hamster has random spawn coordinates and cycle lengths (within one cycle it is either walking around or running on a wheel)
   - These cycle lengths are different between hamsters to avoid all hamsters hopping on to or off of wheels at the same time.
   - Hamsters change cycle lengths in intervals of the length of the maximum cycle length. Within that interval, they always have the same cycle length.
   This is because, due to statelessness, some way to map the current time parameter to every hamster's cycle length is necessary. By the end of this interval, all hamsters would need to have completed their current cycle to avoid snapping to new positions when their cycle length changes.
   - To make this possible, the possible cycle lengths are all divisors of the maximum cycle length. 
   - Within a cycle, there is a random chance for the hamster's goal to either be a random point in space or a specific wheel.
   - If a hamster's last goal was a wheel, then the first half of its next walking phase will instead be used to animate it on the wheel. There still needs to be the second half
   where it walks to its next goal (at double speed) so the cycles transition seamlessly into each other. Due to statelessness, the next cycle is only aware that the hamster must have arrived at its goal and
   can now start moving to the next.
   - For every hamster that is found running on the same wheel within the loop, the wheel "speed" (more accurately, its current degree of rotation) is increased depending on how fast the hamster
   is running. Meaning more hamsters on a wheel generally lead to the wheel turning faster. This rotation is stored in a variable that is both used to animate the hamsters and passed on to
   the wheel rendering step later.
   - When a hamster is running on a wheel, its position is offset depending on the speed that the wheel is moving and a random chance that it stops running and instead is being flung around
   by the wheel. Because this changes the position where it needs to be rendered, these calculations need to be done by every relevant fragment for every hamster to find out if they need to render it.
   - When a hamster is just walking around, its path to the next goal is randomly offset by noise to appear more organic, and it is animated to be bobbing a little bit to seem like it is 
   walking instead of driving there.
2. **The wheel phase**
   - Space is divided into a grid of squares (*jitter groups*) within which everything is jittered uniformly.
   - Each of these jitter groups contains a single wheel.
   - A fragment only needs to check if the wheel of the jitter group that it fits into overlaps with it.
   - When drawing the wheel, its non-stationary parts are rotated by the rotation intensity received from the prior hamster phase.
   - While wheels are drawn on top of the hamsters due to being in a later phase, the hamster color is used to key out specific parts to make the hamster
   appear behind the outer frame of the wheel but in front of the spokes.

#### GUI Parameters
The GUI offers a few parameters for experimenting with the hamster demo code.
- **Time speed**: The speed at which the uniform time parameter changes. Since the demo is stateless, this speed can also be negative to reverse time.
- **Size**: The world size. Larger size means more wheels on screen.
- **Seed**: All pseudo-randomness is based on this seed.
- **Wheel jitter**: Controls the intensity with which the wheel positions are offset to produce less grid-like layouts.
- **Hamster count**: The number of hamsters in the demo. High hamster counts scale poorly with high resolutions.
- **Bobbing speed**: Controls the base speed of the animation of the hamsters bobbing as they move around.
- **Bobbing strength**: Controls the base intensity of the animation of the hamsters bobbing as they move around.
- **Walk noisiness**: The intensity with which the path to the hamsters' next goal is offset by random noise during movement.
- **Wheel desire**: Controls the likelihood in every cycle for the hamsters to decide to run on a wheel as opposed to just walking around aimlessly.

## Splesh
The *splesh* system is a tool for the following challenge: If most of the algorithm should live inside the shader, how can you represent large amounts of potentially
overlapping entities without needing to loop over all entities at every fragment. Since all fragment shader calls are fully parallelized and no state
is stored, the only way to figure out if an entity needs to be rendered on a fragment is to calculate its position and if that position overlaps the fragment.
A loop over **all** entities done at **every** fragment. Not ideal. (This is how the [hamsters demo](#hamsters) does it).

Instead of having a single quad that renders the entire demo, what if we made a mesh out of many smaller quads that each represent an entity?
A **S**plit **MESH**.
Then, calculations, such as determining the position of the entity, can happen on the vertex shader level and focus only on a single entity instead of all
entities that could potentially overlap on a fragment. The vertex shader can easily determine which quad/entity it is currently working on by dividing the vertex index
by four. The quad can then be offset in space to match the entity position through standard vertex shader operations.

The fragment shader only needs to receive the index of the quad from the vertex shader and can focus exclusively on rendering that entity.

For this, [splesh_generator.gd](/scripts/util/splesh_generator.gd) allows generating such a mesh through two main parameters:
1. **num_quads**: The amount of quads. All quads are generated as unit quads around (0,0).
2. **cull_mode**: By default, Godot culls the splesh by its AABB even if the vertex shader has theoretically modified it through shifting vertex positions.
  This parameter allows turning of culling to guarantee that the quads will always be visible even if the pre-vertex-shader-quad is out of frame.

A good example for the use of the splesh system is the [trains demo](#trains). However, there is also a dedicated splesh demo scene that simply shows of a huge amount
of independently moving quads (rendered as colored circles).
My system was able to render 30 million moving "entities" with smooth 60FPS, the real bottleneck beyond this point is generating and storing the giant mesh of quads.


## Trains
The train demo renders an infinitely scalable map covered in train tracks, across which trains made up of a dynamically scalable amounts of cars/segments travel.
For this, the demo is made up of two separate shaders (both making use of [train_tracks.gdshaderinc](/shaders/demos/trains/train_tracks.gdshaderinc) for shared logic):
1. **The background shader** ([trains_background.gdshader](/shaders/demos/trains/trains_background.gdshader)):
   - Renders the train tracks and track joints on a 2D color rect.
2. **The train shader** ([trains_splesh.gdshader](/shaders/demos/trains/trains_splesh.gdshader)):
   - Uses the vertex shader to place every quad of a [splesh](#splesh) at a specific position in space to represent a single train car/segment.
   - Uses the fragment shader to give segments of the same train the same color.

The shader code contains lots of comments explaining how this is achieved in detail. Before
looking at the code though, there are a few things to keep in mind.
The code translates between various coordinate systems depending on the situation:
- **UV space**: The fragment coordinates of the background shader.
- **WORLD space**: The main coordinate system of the background shader. (```UV * global_size```)
- **JITTER GROUP space**: WORLD space is divided into a larger grid in which every fragment in the same jitter group is jittered the same way.
  Every jitter group contains exactly one track joint at its center. Because the different groups jitter differently, this allows for a random looking distribution of joints. (```WORLD / JITTER_BOUNDS```)
- **CIRCUIT space**: JITTER GROUP space is further divided into areas of multiple joints which all always contain a complete circuit. These circuits are picked from a premade selection of circuits and then bridged together. This is done because fully random connections on their own do not have high enough connectivity for good train movement. (```JITTER GROUP / CIRCUIT_SIZE```)
- **VERTEX space**: Coordinates relative to the geometry of the splesh. The position of a train segment needs to be calculated in JITTER GROUP space first to know which joints it has been moving along and then translated into VERTEX space as the output of the vertex shader. (```JITTER GROUP * JITTER_BOUNDS / global_size```)

As mentioned earlier, the background shader first lays out the joints in a grid, then connects them as a set of disjoint circuits, then bridges these circuits randomly, and finally jitters
the track joints for a random looking network. The train shader has trains spawn on random joints at random times and then iteratively calculates their movement over their *lifetime* (which is a modifiable parameter) up to the iteration of the current time uniform. The lifetimes of different trains are offset so that they do not all spawn and respawn at the same time. Since the trains only exist on the GPU and no state is ever saved, this iterative process needs to be redone every frame. However, since it is only calculated on the vertex level and is fully parallelizable between vertices, it is very fast.

To choose which tracks to take at each iteration, the train shader makes use of the same logic as the background shader, being able to move to one of:
- **A**: The previous joint in a circuit (if the current joint is part of a circuit)
- **B**: The next joint in a circuit (if the current joint is part of a circuit)
- **D**: The joint that the outgoing bridge of the current joint is connected to (every joint has one, though it may be part of the circuit and therefore add no new paths)
- **E**: One of the four neighbor joints in the grid (*only if* there exists an incoming bridge from them to the current joint)

While the choice which joint to move to next is random, a choice that would result in the train backtracking to the joint it was at previously is always skipped (unless it is the only possible option) to make movement seem more natural.


#### GUI Parameters
The GUI offers a few parameters for experimenting with the train demo code.
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

## Grid Machine
A grid of randomly sized tiles containing various little animated structures. Entirely shader-based.

The shader works by dividing UV space into smaller tiles and remapping fragment coordinates to new UV coordinates within
their respective tiles so that they can sample their specific animation.

This is done in discrete steps:
1. Every fragment gets its *square_id*, the x and y coordinate of the 1x1 square it falls into.
2. Then, the *gene* of that square is sampled.
   - Multiple squares can combine into a larger tile depending on their gene. So a square having a 2x2 gene means it will combine with 3 other squares to create a larger tile.
   - To make sure every fragment can directly sample its gene without needing to check its neighbors, the possible dimensions (1x1, 1x2, 2x1, 2x2, 4x4) were specifically 
   chosen to be (mostly) squares with side lengths of powers of 2 so that squares with a smaller dimension
   are always fully inside squares with a bigger dimension. For example, a 3x3 could not guarantee non-overlapping alignment with a 2x2, but a 4x4 can.
   - The algorithm starts at the largest gene level, gives it a random chance to take it, and moves to the lower levels if that gene was not randomly taken.
   This way, the larger grene grids block out the smaller ones to ensure that, if one square has gene AxB, all other squares within the AxB square also have that gene.
   - A special case exists for 1x2 and 2x1 since they cannot occupy the same 2x2 square without overlapping: The 2x2 square is used to randomly choose whether the tiles below can become
   a 1x2 or 2x1. Two of the same type can both occupy the same 2x2 without issue.
   - In total this means the algorithm does at most 3 checks: First, 4x4, then 2x2, then *either* 1x2 or 2x1, and if a gene was still not chosen then, the 1x1 gene is picked.
3. Based on the gene dimensions, the fragment UV coordinates are remapped into the tile.

Based on the tiles, the shader does three passes:
1. Fill space with the background color
2. Sample the fragment's tile-specific animation
3. Overlay grid lines on top to separate the tiles

## Switching Tiles
A grid of tiles where two tiles periodically switch places with a little moving animation.
Tiles are rendered with polygons of different colors and vertex counts inside.

Whenever two tiles switch, the one that is animated to move to its new position reveals a tile that looks exactly
like its old neighbor tile behind it and moves on top of the neighbor tile, replacing it.

This shader and script were the first experiment with how well I could partially offload a stateful animation to the shader.
State switches are handled by the script while rendering and animation is handled by the shader.

For this, [switching_tiles.gd](/scripts/demos/switching_tiles/switching_tiles.gd) does the following:
- Depending on what grid size is set in the GUI, it generates a texture with *grid_size* x *grid_size* pixels
  and gives each pixel a random red intensity. Blue and green being left at zero at first.
- In the update function, it checks if enough time has passed for a new tile switch to occur (based on the *speed* parameter in the GUI)
- If a switch needs to occur, it randomly chooses a pixel and a random neighbor. Then it switches the rgb values of both pixels. Additionally, it writes the red value that the neighbor had before the switch into the neighbor's green channel so that the shader can keep track of the old state when animating the change.
- Finally, the script passes the updated texture, the coordinates of the changing pixels and the direction in which the chosen pixel moves to switch with the neighbor to the shader (along with the current time value).

Then, [switching_tiles.gdshader](/shaders/demos/switching_tiles/switching_tiles.gdshader) does the following:
- By mapping the [0.0, 1.0] range of a pixel's red value in the texture that the shader received from the script to one of a set of different *classes*, 
  different tiles can be rendered with polygons of different colors and vertex counts.
- Which pixel value needs to be sampled to get the class of the tile depends on which of the following cases the fragment falls on to
  (determined through the state texture and the shader uniforms received from the script):
  1. The fragment falls onto a tile that is not involved in the current switch. Its class is sampled from the red value of pixel that represents the entire tile in the texture.
  2. The fragment falls onto a tile that was the chosen neighbor of the randomly chosen pixel for the current switch. Here, the class needs to be sampled from the pixel's green value because red already contains the switched value of the tile that should only be rendered after the change has been animated.
  3. The fragment falls onto the tile that was the original position of the randomly chosen pixel. The class is immediately sampled from the new red value because the moving tile is going to be animated moving away from this square to its new position and leaving behind a tile with the old neighbor's value.
  4. The fragment falls onto the in-between-grid position of the tile that is being animated to move to its new grid position. The position of the moving tile depends on the time parameter.
  In this case, the class is sampled from the red value of the grid square that it will arrive at once the animation has finished. 
- To sample the polygon correctly, the fragment's UV coordinates are remapped into the range of the tile. For the moving tile, the coordinate offset needs to be taken into account.

#### GUI Parameters
The GUI offers the following parameters for experimenting with the tile demo code.
- **Size**: The side length (number of tiles) of the tile grid.
- **Speed**: The speed with which the tile switches occur.
