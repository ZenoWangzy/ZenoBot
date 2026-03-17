#!/usr/bin/env python3
import os
import pty
import sys


def main() -> int:
    if len(sys.argv) < 5:
        print("usage: claude-pty-run.py <workdir> <output_file> <exit_file> <cmd...>", file=sys.stderr)
        return 2

    workdir = sys.argv[1]
    output_file = sys.argv[2]
    exit_file = sys.argv[3]
    cmd = sys.argv[4:]

    os.chdir(workdir)

    with open(output_file, "ab", buffering=0) as out:
        def master_read(fd: int) -> bytes:
            data = os.read(fd, 1024)
            if data:
                out.write(data)
            return data

        status = pty.spawn(cmd, master_read=master_read)

    if hasattr(os, "waitstatus_to_exitcode"):
        rc = os.waitstatus_to_exitcode(status)
    else:
        rc = status >> 8

    with open(exit_file, "w", encoding="utf-8") as f:
        f.write(str(rc))

    return rc


if __name__ == "__main__":
    raise SystemExit(main())
