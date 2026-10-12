#!/usr/bin/env python3
"""Compile the actual patched configuration code with a filesystem-backed SAF test adapter.
Requires JDK 17, Kotlin compiler, and the project's ini4j 0.5.4 jar; no Android SDK needed.
These are configuration integration tests, not an Android/device build or UI test.
"""
import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('source', type=Path, help='patched source checkout')
p.add_argument('--kotlinc', required=True)
p.add_argument('--ini4j', type=Path, required=True)
p.add_argument('--output', type=Path, default=Path('.work/config-tests'))
a = p.parse_args()
out = a.output.resolve(); out.mkdir(parents=True, exist_ok=True)
java = out / 'stubs'; java.mkdir(exist_ok=True)
src = a.source.resolve() / 'src/android/app/src/main/java/org/citra/citra_emu'
stubs = {
'android/net/Uri.java': '''package android.net; public class Uri {
 public final String path; public Uri(String s){path=s;} public static Uri parse(String s){return new Uri(s);}
 public String toString(){return path;}}''',
'android/content/Context.java': '''package android.content; public class Context {
 public ContentResolver getContentResolver(){return new ContentResolver();}
 public String getString(int id,Object... args){return "message";}}''',
'android/content/ContentResolver.java': '''package android.content; import java.io.*; public class ContentResolver {
 public InputStream openInputStream(android.net.Uri u) throws IOException {return new FileInputStream(u.path);}
 public OutputStream openOutputStream(android.net.Uri u,String mode) throws IOException{return new FileOutputStream(u.path);}}''',
'android/text/TextUtils.java': '''package android.text; public class TextUtils {public static boolean isEmpty(CharSequence s){return s==null||s.length()==0;}}''',
'androidx/documentfile/provider/DocumentFile.java': '''package androidx.documentfile.provider; import java.io.*; import android.net.Uri;
 public class DocumentFile {private final File f; public DocumentFile(File file){f=file;}
 public static DocumentFile fromTreeUri(android.content.Context c,Uri u){return new DocumentFile(new File(u.path));}
 public DocumentFile findFile(String n){File v=new File(f,n);return v.exists()?new DocumentFile(v):null;}
 public DocumentFile createDirectory(String n){File v=new File(f,n);return v.mkdirs()||v.isDirectory()?new DocumentFile(v):null;}
 public DocumentFile createFile(String type,String n) throws IOException {File v=new File(f,n);if(!v.exists()&&!v.createNewFile())return null;return new DocumentFile(v);}
 public Uri getUri(){return new Uri(f.getPath());} public long length(){return f.length();} public boolean delete(){return f.delete();}}''',
'org/citra/citra_emu/CitraApplication.java': '''package org.citra.citra_emu; public class CitraApplication {public static android.content.Context appContext=new android.content.Context();}''',
'org/citra/citra_emu/utils/DirectoryInitialization.java': '''package org.citra.citra_emu.utils; public class DirectoryInitialization {public static String userDirectory;}''',
'org/citra/citra_emu/utils/Log.java': '''package org.citra.citra_emu.utils; public class Log {public static void error(String s){throw new AssertionError(s);}}''',
'org/citra/citra_emu/utils/FileUtil.java': '''package org.citra.citra_emu.utils; public class FileUtil {public static androidx.documentfile.provider.DocumentFile createFile(String d,String n) throws java.io.IOException {return new androidx.documentfile.provider.DocumentFile(new java.io.File(d)).createFile("text/plain",n);}}''',
}
# Include real model classes and SettingsFile. Only the native JNI key provider is replaced
# (it returns literal INI keys on Android); enums/parser/merge/save code are untouched.
files = list((src/'features/settings/model').glob('*.kt'))
files = [f for f in files if f.stem in {'Settings','SettingSection','BooleanSetting','IntSetting','FloatSetting','ScaledFloatSetting','StringSetting','IntListSetting'} or f.stem.startswith('Abstract')]
files += [src/'features/settings/utils/SettingsFile.kt', src/'features/settings/utils/PerGameSettings.kt', src/'features/settings/ui/SettingsActivityView.kt',src/'utils/BiMap.kt']
refs = {}
for f in files:
 for kind, name in re.findall(r'R\.(\w+)\.(\w+)',f.read_text()): refs.setdefault(kind,set()).add(name)
stubs['org/citra/citra_emu/R.java']='package org.citra.citra_emu; public class R {'+''.join('public static class '+k+' {'+''.join(f'public static final int {n}=1;' for n in sorted(v))+'}' for k,v in refs.items())+'}'
for path, text in stubs.items():
 dest=java/path; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_text(text)
keys=(src/'features/settings/SettingKeys.kt').read_text()
keys=re.sub(r'external fun (\w+)\(\): String',lambda m:f'fun {m[1]}(): String = "{m[1]}"',keys)
keyfile=out/'SettingKeys.kt'; keyfile.write_text(keys)
classes=out/'classes'; classes.mkdir(exist_ok=True)
subprocess.run(['javac','-d',str(classes),*[str(f) for f in java.rglob('*.java')]],check=True)
jar=out/'tests.jar'
subprocess.run([a.kotlinc,'-classpath',os.pathsep.join([str(classes),str(a.ini4j.resolve())]),*[str(f) for f in files],str(keyfile),str(Path(__file__).with_name('ConfigurationRegression.kt').resolve()),'-include-runtime','-d',str(jar)],check=True)
with tempfile.TemporaryDirectory(prefix='userdata-', dir=out) as userdata:
    subprocess.run(['java','-cp',os.pathsep.join([str(jar),str(classes),str(a.ini4j.resolve())]),'ConfigurationRegressionKt',userdata],check=True)
