# PSX Dithering With Compositor Effects
This project is using [perfoon](https://github.com/perfoon/Abandoned-Spaceship-Godot-Demo/commits?author=perfoon)'s [Abandoned Spaceship](https://github.com/perfoon/Abandoned-Spaceship-Godot-Demo/commits?author=perfoon) Scenes.

# Compositor Effects
There are different compositor effects to the finish look:
- Chromatic Aberration
- PSX Dithering
- Palette Remap
- Hard Light Contrast
- Vignette

# Scenes
There are two main scenes og importance:
- PostProcessHangar: which has the **Shader Material** with the *postprocess.gdshader*.
- CompositorEffectHangar: which is the translation of said shader into various compositor effects.

# Other Shaders
For cleaning and debugging reasons, there are various shaders that are used only for issue solving purposes, but are there if wanna be seen. Most are copied from ShaderToy so is necessary to check their respective licenses if wanna be used...
