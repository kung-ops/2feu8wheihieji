"""Writes R.java for a package from apktool's res/values/public.xml."""
import sys
import xml.etree.ElementTree as ET

pkg, public_xml = sys.argv[1], sys.argv[2]
types = {}
for e in ET.parse(public_xml).getroot():
    types.setdefault(e.get("type"), []).append((e.get("name"), e.get("id")))

out = ["package %s;" % pkg, "", "public final class R {"]
for t in sorted(types):
    out.append("    public static final class %s {" % t)
    for name, rid in types[t]:
        out.append("        public static final int %s = %s;" % (name.replace(".", "_"), rid))
    out.append("    }")
out.append("}")
print("\n".join(out))
