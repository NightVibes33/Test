#!/usr/bin/env python3
"""Remove a physical dock controller that is absent in qemu-sptm.

Applies to an already unwrapped and darwin-vm-fixed-up ADT. No Apple binaries
are shipped; modifications take place on ephemeral CI firmware inputs.
"""
import argparse
import importlib.util
import json
from pathlib import Path

TARGET = "dock-connect"

def edit_tree(path, upstream_python):
    spec = importlib.util.spec_from_file_location("darwin_vm_dt_fixup", upstream_python)
    if spec is None or spec.loader is None:
        raise ValueError("Cannot import upstream ADT codec")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    node = module.ADTNode()
    data = Path(path).read_bytes()
    module.decode_node(data, node)
    removed = []
    def recurse(parent, current=""):
        for child in list(parent.children):
            name = child.props.get("name", "")
            if isinstance(name, bytes):
                name = name.split(b"\0", 1)[0].decode("utf-8", "replace")
            loc = current + "/" + name
            if name == TARGET or name.startswith(TARGET + "@"):
                parent.children.remove(child)
                removed.append(loc)
            else:
                recurse(child, loc)
    recurse(node)
    if not removed:
        raise ValueError("No AppleDockConnect dock-connect ADT node found; refusing silent no-op")
    patched = module.encode_node(node)
    check = module.ADTNode()
    module.decode_node(patched, check)
    if len(patched) >= len(data):
        raise ValueError("Dock node was not actually removed")
    Path(path).write_bytes(patched)
    return {
        "policy": "remove physical AppleDockConnect controller absent from qemu-sptm",
        "removed_paths": removed,
        "original_tree_bytes": len(data),
        "patched_tree_bytes": len(patched),
        "native_homeview_setup_running": False,
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dtree")
    ap.add_argument("--upstream", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    data = edit_tree(args.dtree, args.upstream)
    Path(args.report).write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()
