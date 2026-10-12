@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" x86 >nul
cd /d "%~dp0"
set D8=..\third_party\d3d8to9\source
cl /nologo /O2 /MT /LD /EHsc /std:c++17 /DD3D8TO9NOLOG /I%D8% d3d8proxy.cpp %D8%\d3d8to9.cpp %D8%\d3d8to9_base.cpp %D8%\d3d8to9_device.cpp %D8%\d3d8to9_index_buffer.cpp %D8%\d3d8to9_surface.cpp %D8%\d3d8to9_swap_chain.cpp %D8%\d3d8to9_texture.cpp %D8%\d3d8to9_vertex_buffer.cpp %D8%\d3d8to9_volume.cpp %D8%\d3d8types.cpp %D8%\interface_query.cpp msm_reflect.cpp msm_graphics.cpp /Fo.\obj\ /link /DEF:..\third_party\d3d8to9\res\d3d8.def /OUT:d3d8.dll d3d9.lib user32.lib kernel32.lib gdi32.lib shell32.lib winmm.lib
