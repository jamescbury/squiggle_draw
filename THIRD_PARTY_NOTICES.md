# References and dependencies

The original Swift and Java application code is provided under the root MIT license. The following projects retain their respective terms; the root license does not relicense them.

## Algorithm references

- Chiu et al., [Tone- and Feature-Aware Circular Scribble Art (2015)](https://cgv.cs.nthu.edu.tw/projects/Recreational_Graphics/CircularScribbleArt). Research inspiration. Author source code, tone lookup tables, example photographs, and paper figures are not distributed here. This project is an independent approximation, not a reproduction of reported paper benchmarks.
- [ugocapeto/thescribbler](https://github.com/ugocapeto/thescribbler). Initial study reference; its source is not bundled.
- [Gregg Wygonik's SquiggleDraw](https://github.com/gwygonik/SquiggleDraw), with contributions by Windell H. Oskay. Row-wave inspiration; upstream is Unlicense/public domain. The legacy Swift wave implementation is independently written.
- [StippleGen 2](https://www.evilmadscientist.com/2012/stipplegen2/). Weighted stippling and rounded-tour inspiration; upstream implementation is not bundled.

## Android build dependencies

Gradle retrieves dependencies from the repositories declared in `squiggle-player/settings.gradle`; dependency source trees are not vendored. Binary distributors must preserve dependency license notices.

- Gradle wrapper: Apache-2.0, [Gradle license](https://github.com/gradle/gradle/blob/master/LICENSE).
- AndroidX Core and Android build/test libraries: [Android Open Source Project licensing](https://source.android.com/docs/setup/about/licenses).
- BOOX `onyxsdk-device:1.3.5.2`: vendor SDK from the official BOOX Maven repository. The [official demonstration project license](https://github.com/onyx-intl/OnyxAndroidDemo/blob/master/LICENSE) is Apache-2.0; consult the vendor SDK artifact terms when redistributing binaries.
- LSPosed HiddenApiBypass 6.1: [Apache-2.0](https://github.com/LSPosed/AndroidHiddenApiBypass/blob/main/LICENSE). Used only for the explicit BOOX framework compatibility route.
- JUnit and Robolectric: test-only dependencies, not application features. Consult their published licenses.

## Sample images

Only four AI-generated reference inputs are included: shell, apple, pear and pitcher, mountain lake. Their generation prompts and origin are recorded in `squiggle-draw/Sources/SquiggleDraw/Resources/Samples/provenance.json`. They were selected by the project owner for this sample gallery. They contain no family photos or real private individuals. Generated preview outputs use only these listed inputs.
