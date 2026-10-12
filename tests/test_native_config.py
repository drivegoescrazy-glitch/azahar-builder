"""Read the delivered C++ selectors against the real INIReader library, not a reimplementation."""
import subprocess
import unittest
from pathlib import Path
from test_native_patches import function

ROOT = Path(__file__).resolve().parents[1]


class NativeConfigTest(unittest.TestCase):
    def test_title_overlay_normal_speed_and_startup_order(self):
        cpp=ROOT/'.work/source/src/android/app/src/main/jni/config.cpp'
        native=(cpp.parent/'native.cpp').read_text()
        run=function(native,'static Core::System::ResultStatus RunCitra(')
        self.assertLess(run.index('Config{'),run.index('Settings::GetWorkingGraphicsAPI()'))
        text=cpp.read_text()
        # Compile the exact delivered value-selection statements; setting assignment only is
        # adapted, while the INIReader and overlay selection are the actual implementation.
        source=function(text,'INIReader& Config::SourceFor(')
        a=text.index('    // A global 60 FPS flag');b=text.index('    ReadSetting("Renderer", Settings::values.render_3d);',a)
        read=text[a:b].replace('ReadSetting("Renderer", Settings::values.frame_limit);',
            'Settings::values.frame_limit = SourceFor("Renderer", "frame_limit").GetInteger("Renderer", "frame_limit", 100);')
        out=ROOT/'.work/native-config';out.mkdir(exist_ok=True)
        lib=ROOT/'.work/inih'
        if not lib.exists():
            # Fixture dependency from the already checked-out upstream clone; never committed.
            original=Path('/tmp/pristine/externals/inih/inih')
            self.assertTrue(original.exists(),'Provide upstream inih at .work/inih for this test')
            import shutil
            shutil.copytree(original,lib)
        unit=r'''
#include <memory>
#include <string>
#include <cassert>
#include <iostream>
#include "INIReader.h"
namespace Settings {
struct Bool {bool v=false; Bool& operator=(bool b){v=b;return *this;} bool GetValue(){return v;}};
struct {Bool use_60fps_patch; int frame_limit=100;} values;
}
class Config {
public:
 std::unique_ptr<INIReader> android_config,game_config;
 Config(const std::string& global,const std::string& custom){
 android_config=std::make_unique<INIReader>(global.c_str(),global.size());
 if(!custom.empty())game_config=std::make_unique<INIReader>(custom.c_str(),custom.size());}
 INIReader& SourceFor(const std::string&,const std::string&);
 void read(){
'''+read+r'''
 }
};
'''+source+r'''
int main(){
 std::string global="[Renderer]\nresolution_factor=2\nuse_60fps_patch=1\nframe_limit=200\nuse_frame_limit=0\n";
 Config first(global,"[Renderer]\nresolution_factor=4\nuse_60fps_patch=true\n");
 Config second(global,"[Renderer]\nresolution_factor=1\n");
 assert(first.SourceFor("Renderer","resolution_factor").GetInteger("Renderer","resolution_factor",0)==4);
 assert(second.SourceFor("Renderer","resolution_factor").GetInteger("Renderer","resolution_factor",0)==1);
 first.read();assert(Settings::values.use_60fps_patch.GetValue() && Settings::values.frame_limit==100);
 second.read();assert(!Settings::values.use_60fps_patch.GetValue() && Settings::values.frame_limit==0);
 Config normal(global,"");normal.read();assert(!Settings::values.use_60fps_patch.GetValue());
 std::cout<<"PASS: actual native title selectors, 4x/1x isolation, ignore global FPS flag, normal-speed FPS mode, config before graphics construction\n";
}
'''
        # Raw C++ fixture uses escaped newline sequences; actual config text needs newline chars.
        unit=unit.replace('\\\\n','\\n')
        (out/'test.cpp').write_text(unit)
        subprocess.run(['g++','-std=c++20','-O1','-I'+str(lib/'cpp'),'-I'+str(lib),str(out/'test.cpp'),str(lib/'cpp/INIReader.cpp'),str(lib/'ini.c'),'-o',str(out/'test')],check=True)
        subprocess.run([str(out/'test')],check=True)


if __name__=='__main__':unittest.main()
