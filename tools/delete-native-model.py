"""Remove one exact Model from Rojo's native XML representation of a bundle."""
import sys
import xml.etree.ElementTree as ET

def signature(file):
    root = ET.parse(file).getroot()
    referents = {item.get("referent"): str(i) for i, item in enumerate(root.iter("Item"))
                 if item.get("referent") is not None}
    shared = {value.get("md5"): value.text for value in root.findall("SharedStrings/SharedString")}

    def node(element):
        attributes = dict(element.attrib)
        if "referent" in attributes:
            attributes["referent"] = referents[attributes["referent"]]
        text = element.text if not len(element) else None
        if element.tag == "Ref":
            text = referents.get(text, text)
        if element.tag == "SharedString":
            text = shared.get(text, text)
        if element.tag in {f"R{r}{c}" for r in range(3) for c in range(3)} and text is not None:
            # Binary Rojo serialization canonicalizes near-axis rotations.
            if abs(float(text)) < 1e-6:
                text = "0"
        return element.tag, attributes, text, [node(child) for child in element if child.tag != "SharedStrings"]

    return node(root)

if sys.argv[1] == "--verify":
    if signature(sys.argv[2]) != signature(sys.argv[3]):
        sys.exit("Bundle round-trip changed remaining native data")
    sys.exit(0)

source, output, model_path = sys.argv[1:]
tree = ET.parse(source)
root = tree.getroot()
items = root.findall("Item")
if len(items) != 1 or items[0].get("class") != "Folder":
    sys.exit("Expected one bundle root Folder")
parent = items[0]
segments = model_path.split("/")
for index, name in enumerate(segments):
    matches = [child for child in parent.findall("Item")
               if child.findtext("Properties/*[@name='Name']") == name]
    expected = "Model" if index == len(segments) - 1 else "Folder"
    if len(matches) != 1 or matches[0].get("class") != expected:
        sys.exit(f"Bundle path is missing or ambiguous at {name!r}")
    target = matches[0]
    if expected == "Folder":
        parent = target
removed = {item.get("referent") for item in target.iter("Item")}
removed.discard(None)
parent.remove(target)
if any(ref.text in removed for ref in root.iter("Ref")):
    sys.exit("A remaining instance references the selected model")
tree.write(output, encoding="utf-8", xml_declaration=True)
