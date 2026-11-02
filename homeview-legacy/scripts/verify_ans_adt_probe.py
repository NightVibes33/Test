#!/usr/bin/env python3
"""Verify an ANS compatibility experiment uses ORIGINAL Apple ADT values only.

No assertion of real ANS/NAND hardware functionality is made by this utility.
"""
import argparse
import importlib.util
import json
from pathlib import Path

PATHS = ("/arm-io/ans", "/arm-io/ans/iop-ans-nub", "/arm-io/sart-ans")


def index_tree(root):
    props, nodes = {}, {}
    def visit(node, path="/"):
        if path in nodes:
            raise ValueError("Duplicate node: " + path)
        names = [c.props.get("name") for c in node.children]
        if len(set(names)) != len(names):
            raise ValueError("Duplicate ADT child: " + path)
        nodes[path] = names
        for name, value in node.props.items():
            props[path, name] = value
        for name, child in zip(names, node.children):
            if not isinstance(name, str) or not name:
                raise ValueError("Invalid Apple node name")
            visit(child, path.rstrip("/") + "/" + name)
    visit(root)
    return props, nodes


def verify_nodes(control, probe, raw):
    c, cn = index_tree(control)
    p, pn = index_tree(probe)
    r, rn = index_tree(raw)
    if cn != pn:
        raise ValueError("Unexpected ADT node topology difference")
    changed = set()
    for key in set(c) | set(p):
        if c.get(key) != p.get(key):
            changed.add(key)
    allowed = {(path, "compatible") for path in PATHS}
    if not changed or changed - allowed:
        raise ValueError("ANS probe changed non-allowlisted ADT fields: " + repr(changed-allowed))
    missing = []
    for path in PATHS:
        key = (path, "compatible")
        if key not in p or key not in r or p[key] != r[key]:
            raise ValueError("ANS probe did not preserve exact Apple original: " + path)
        if key not in changed:
            missing.append(path)
    return {
        "changed_properties": sorted(path + "/compatible" for path, _ in changed),
        "original_apple_compatible_values_preserved": True,
        "all_other_ADT_fields_unchanged": True,
        "already_retained_without_probe": missing,
        "true_ANS_or_NAND_device_implemented": False,
        "driver_match_observed": False,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("control")
    ap.add_argument("probe")
    ap.add_argument("raw")
    ap.add_argument("--upstream", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location("apple_dt", args.upstream)
    if not spec or not spec.loader:
        raise ValueError("Cannot load original Apple ADT decoder")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    trees = []
    for file in (args.control, args.probe, args.raw):
        root = mod.ADTNode()
        mod.decode_node(Path(file).read_bytes(), root)
        trees.append(root)
    data = verify_nodes(*trees)
    dest = Path(args.report)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
