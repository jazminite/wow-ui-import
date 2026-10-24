"""Runs tests/run.lua on Lua 5.1 through lupa, for machines without Lua.

    python -m pip install lupa
    python tests/run_with_lupa.py
"""
import os
import sys

import lupa.lua51 as lua51

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
runtime = lua51.LuaRuntime()
exit_code = runtime.execute("""
    local realExit = os.exit
    local code = 0
    os.exit = function(c) code = c or 0 end
    dofile("tests/run.lua")
    os.exit = realExit
    return code
""")
sys.exit(exit_code or 0)
