"""Compile and exercise the delivered native patch functions (synthetic code, not a game)."""
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.work/source/src/core/file_sys'


def function(text, signature):
    start = text.index(signature)
    opened = text.index('{', start)
    depth = 1
    end = opened + 1
    while depth:
        if text[end] == '{': depth += 1
        if text[end] == '}': depth -= 1
        end += 1
    return text[start:end]


class NativePatchTest(unittest.TestCase):
    def test_real_ips_and_code_layering(self):
        out = ROOT/'.work/native-tests'
        out.mkdir(exist_ok=True)
        ips = function((SOURCE/'patch.cpp').read_text(), 'Loader::ResultStatus ApplyIpsPatch(')
        layer = function((SOURCE/'ncch_container.cpp').read_text(), 'Loader::ResultStatus NCCHContainer::ApplyCodePatch(')
        unit = r'''
#include <vector>
#include <string>
#include <fstream>
#include <filesystem>
#include <cassert>
#include <cstring>
#include <cstdint>
#include <iostream>
using u8=uint8_t; using u32=uint32_t; using u64=uint64_t;
#define LOG_INFO(...) ((void)0)
namespace Loader { enum class ResultStatus {Success,ErrorNotUsed,ErrorPatches}; }
namespace FileUtil {
enum class UserPath {SDMCDir};
std::string root;
std::string GetUserPath(UserPath) {return root+"/sd/";}
class IOFile {
 std::ifstream input;
public:
 IOFile(std::string path,const char*) : input(path,std::ios::binary) {}
 explicit operator bool() const {return input.is_open();}
 size_t GetSize(){auto pos=input.tellg();input.seekg(0,std::ios::end);auto end=input.tellg();input.seekg(pos);return end;}
 size_t ReadBytes(void* data,size_t size){input.read(static_cast<char*>(data),size);return input.gcount();}
};
}
namespace fmt {
std::string format(const char*, const std::string& base,u64){return base+"code.ips";}
}
namespace FileSys {
namespace Patch {
'''+ips+r'''
// BPS is deliberately incompatible in this harness: the loader must return the failure,
// not pretend that a failed source-checksum patch succeeded.
Loader::ResultStatus ApplyBpsPatch(const std::vector<u8>&,std::vector<u8>&){return Loader::ResultStatus::ErrorPatches;}
}
std::vector<std::string> roots;
std::vector<std::string> GetModsPaths(u64){return roots;}
class NCCHContainer {
public:
 struct {u64 program_id=0x0004000000000001;} ncch_header;
 std::string filepath;
 Loader::ResultStatus ApplyCodePatch(std::vector<u8>& code) const;
};
'''+layer+r'''
}
void write(const std::string& path,const std::vector<u8>& data){
 std::filesystem::create_directories(std::filesystem::path(path).parent_path());
 std::ofstream file(path,std::ios::binary);file.write(reinterpret_cast<const char*>(data.data()),data.size());
}
std::vector<u8> patch(u8 offset,u8 value){return {'P','A','T','C','H',0,0,offset,0,1,value,'E','O','F'};}
int main(int argc,char** argv){
 using namespace FileSys; using Loader::ResultStatus;
 FileUtil::root=argv[1];
 std::filesystem::remove_all(FileUtil::root); std::filesystem::create_directories(FileUtil::root);
 std::vector<u8> code(8,0);
 assert(Patch::ApplyIpsPatch(patch(1,23),code)==ResultStatus::Success && code[1]==23);
 for(size_t n=0;n<8;n++){
  std::vector<u8> bad(n,0);
  assert(Patch::ApplyIpsPatch(bad,code)==ResultStatus::ErrorPatches);
 }
 auto truncated=patch(1,23);truncated.resize(10);
 assert(Patch::ApplyIpsPatch(truncated,code)==ResultStatus::ErrorPatches);
 assert(Patch::ApplyIpsPatch(patch(12,23),code)==ResultStatus::ErrorPatches);
 std::vector<u8> rle={'P','A','T','C','H',0,0,2,0,0,0,3,11,'E','O','F'};
 assert(Patch::ApplyIpsPatch(rle,code)==ResultStatus::Success && code[2]==11 && code[4]==11);
 NCCHContainer ncch;
 auto normal=FileUtil::root+"/mods/";auto fps=FileUtil::root+"/60fps/";
 roots={normal};
 assert(ncch.ApplyCodePatch(code)==ResultStatus::ErrorNotUsed);
 write(normal+"exefs/code.ips",patch(0,42));
 code.assign(8,0);
 assert(ncch.ApplyCodePatch(code)==ResultStatus::Success && code[0]==42);
 write(fps+"exefs/code.ips",patch(1,60));
 roots={fps,normal};code.assign(8,0);
 assert(ncch.ApplyCodePatch(code)==ResultStatus::Success && code[0]==42 && code[1]==60);
 write(fps+"exefs/code.ips",patch(0,60));code.assign(8,0);
 assert(ncch.ApplyCodePatch(code)==ResultStatus::Success && code[0]==60);
 std::filesystem::remove(fps+"exefs/code.ips");
 write(fps+"exefs/code.bps",{'B','P','S','1',0,0,0,0});
 assert(ncch.ApplyCodePatch(code)==ResultStatus::ErrorPatches);
 std::cout<<"PASS: real IPS normal/RLE, malformed/truncated/bounds safety, regular+FPS patch order, failure propagation\n";
}
'''
        cpp = out/'native.cpp'
        cpp.write_text(unit)
        binary = out/'native-tests'
        subprocess.run(['g++','-std=c++20','-O1','-g','-fsanitize=address,undefined',str(cpp),'-o',str(binary)],check=True)
        subprocess.run([str(binary),str(out/'userdata')],check=True)


if __name__ == '__main__':
    unittest.main()
