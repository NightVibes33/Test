#!/usr/bin/env python3
"""Verify a causal Apple ADT experiment: exactly one synthetic property differs.

This establishes source-ADT equivalence, NOT that libMobileGestalt consumes
/chosen/PumpkinMode. All differences except one explicitly named u32 are fatal.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def walk(node, path="/"):
    """Return paths to properties; forbid ambiguous/duplicated child names."""
    properties = {}
    topology = {}
    def visit(current, current_path):
        if current_path in topology:
            raise ValueError("Duplicate ADT path: " + current_path)
        children = [c.props.get("name") for c in current.children]
        if any(not isinstance(name, str) or not name for name in children):
            raise ValueError("Unnamed ADT child at " + current_path)
        if len(set(children)) != len(children):
            raise ValueError("Duplicate ADT child at " + current_path)
        topology[current_path] = children
        for name, value in current.props.items():
            properties[(current_path, name)] = value
        for child, name in zip(current.children, children):
            visit(child, current_path.rstrip("/") + "/" + name)
    visit(node, path)
    return properties, topology


def compare_nodes(control_root, experimental_root):
    control, control_tree = walk(control_root)
    experimental, experimental_tree = walk(experimental_root)
    if control_tree != experimental_tree:
        raise ValueError("Node topology or child ordering changed between ADT variants")
    target = ("/chosen", "PumpkinMode")
    if target in control:
        raise ValueError("Control already has a PumpkinMode property")
    if target not in experimental:
        raise ValueError("Experimental ADT missing PumpkinMode property")
    raw_value = experimental[target]
    if not isinstance(raw_value, str) or not raw_value.startswith("u32:"):
        raise ValueError("Expected a u32 PumpkinMode property")
    try:
        value = int(raw_value[4:], 0)
    except ValueError as exc:
        raise ValueError("Invalid PumpkinMode u32 value") from exc
    if value != 1:
        raise ValueError("Expected experimental PumpkinMode=1")
    expected = dict(control)
    expected[target] = raw_value
    changed = sorted(
        (path + "/" + name for path, name in set(expected) | set(experimental)
         if expected.get((path, name)) != experimental.get((path, name))),
    )
    if changed:
        raise ValueError("Other Apple ADT fields changed: " + repr(changed[:30]))
    return {"exactly_one_property_added": True,
            "property": "/chosen/PumpkinMode",
            "control_property_present": False,
            "experimental_property_value": 1,
            "all_other_nodes_and_properties_identical": True,
            "mobilegestalt_reads_property_verified": False}


def verify(control_file, experimental_file, upstream):
    spec = importlib.util.spec_from_file_location("homeview_adtdiff", upstream)
    if not spec or not spec.loader:
        raise ValueError("Cannot load matching Apple ADT decoder")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    paths = [Path(control_file), Path(experimental_file)]
    trees = []
    for path in paths:
        node = mod.ADTNode()
        mod.decode_node(path.read_bytes(), node)
        trees.append(node)
    result = compare_nodes(*trees)
    result["control_sha256"] = hashlib.sha256(paths[0].read_bytes()).hexdigest()
    result["experimental_sha256"] = hashlib.sha256(paths[1].read_bytes()).hexdigest()
    result["method"] = "decoded full ADT property and ordered topology equality"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("control")
    parser.add_argument("experimental")
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    result = verify(args.control, args.experimental, args.upstream)
    path = Path(args.report)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
