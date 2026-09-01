#!/usr/bin/env python3
"""Make chains-project maven-lockfile output digestible by hermeto (cachi2) x-maven.

Two defects in the generated lockfiles break hermeto's experimental x-maven
prefetch. Both stem from maven-lockfile recording entries that it could not
attribute to a remote repository (empty/absent ``resolved`` / ``checksum``).

1. Local reactor parent references (``parent`` / ``parentPom`` / nested ``pom``)
   -------------------------------------------------------------------------
   Every module's Maven parent is our *local* root module
   ``dev.knative.eventing.kafka.broker:data-plane`` (``relativePath``), recorded
   WITHOUT a ``resolved`` key. It appears not only as the top-level
   ``pom.parent`` but also as the ``parentPom`` of every reactor-sibling
   dependency (``contract`` -> ``core`` -> ``dispatcher`` ...), at every nesting
   depth. hermeto's ``_extract_pom_chain`` (``models.py``) calls
   ``MavenArtifact.model_validate`` on each such node, and ``resolved`` is a
   required field ->

       ValidationError: 1 validation error for MavenArtifact
       resolved  Field required [type=missing]

   (Note: reactor-sibling *dependencies* carry ``"resolved": ""`` -- present but
   empty -- so they pass validation; only the parent nodes omit the key and
   crash.) The BOM imports declared by that parent (quarkus-bom, jackson-bom,
   opentelemetry-bom, micrometer-bom) *are* remote and must be prefetched; they
   live under the parent's ``boms``, and hermeto iterates an artifact's ``boms``
   directly. So for each local, unresolved parent node we hoist its ``boms`` onto
   the containing artifact and delete the parent reference. The one node we must
   NOT delete is the module's own top-level ``pom`` (hermeto reads it as the root
   pom); we still strip ITS local ``parent``. -> ``strip_local_parents``.

2. External artifacts with empty ``resolved``
   ------------------------------------------
   maven-lockfile sometimes leaves ``resolved``/``checksum`` empty (``""``) for a
   remote productized artifact it failed to attribute (seen with the
   ``.redhat-00001`` builds of ``protobuf-java-util`` and, transitively,
   ``vertx-mutiny-generator``). Their ``parentPom`` DOES carry a ``resolved`` URL
   (``maven.repository.redhat.com``), so the jars exist there; hermeto then tries
   to "download" an empty URL and dies with ``FetchError: Could not download``.
   We reconstruct the jar URL from the sibling ``parentPom.resolved`` (repo base
   + repositoryId), fetch the jar once and record its sha256.
   -> ``backfill_external``. (A fully clean lockfile regeneration also fixes this
   class at the source, so this pass is often a no-op; it is kept as a safety
   net and is idempotent.)

3. Reactor-internal sibling *dependencies* with empty ``resolved``
   --------------------------------------------------------------
   Every submodule lists its reactor siblings as dependencies
   (``dev.knative.eventing.kafka.broker:*`` with ``"resolved": ""`` -- present
   but empty). These are built from source in the same reactor, so no remote
   jar exists. Unlike the local *parent* nodes (defect 1, which omit ``resolved``
   and crash validation), these PASS ``MavenArtifact.model_validate`` (the key is
   present) and reach the download phase, where hermeto fetches the empty URL and
   dies with ``FetchError: Could not download``. They cannot be back-filled (no
   remote artifact) and must not simply be deleted: each carries the module's
   real external transitive dependencies under ``children`` (e.g. ``dispatcher``
   -> ``bucket4j-core``, ``kubernetes-httpclient-vertx``, and ``core`` which nests
   28 more). So we *splice* them: drop each reactor-local empty node from its
   ``dependencies``/``children`` list and hoist its (recursively spliced) children
   into its place, preserving every external descendant. hermeto flattens the
   dependency forest into a de-duplicated set, so the resulting duplicates are
   harmless. -> ``splice_local_deps``.

4. External leaf dependencies whose Maven parent POM is never prefetched
   --------------------------------------------------------------------
   maven-lockfile records the full ``parentPom`` chain for many artifacts, but
   NOT for some transitive leaf dependencies -- even with ``-DincludeParentPom``
   on (the default). Such a node carries only a string ``"parent"`` (its
   *dependency-tree* parent, e.g. ``"parent":
   "io.micrometer:micrometer-core:..."``) and no ``parentPom``, so hermeto never
   learns about the artifact's *Maven* parent POM. hermeto fetches each jar's
   sibling ``.pom``, but does not itself follow the ``<parent>`` declared inside
   it. If that parent POM is not otherwise in the prefetch set (i.e. it is not
   another artifact's jar/pom or another node's recorded parentPom), the offline
   build fails reading the dependency's descriptor::

       Failed to read artifact descriptor for org.latencyutils:LatencyUtils:jar:2.0.3.redhat-00005
       Caused by: ... org.sonatype.oss:oss-parent:pom:7.0.0.redhat-00018 (absent):
       Cannot access hermeto-local (file:///cachi2/output/deps/maven) in offline mode ...

   For every external jar node WITHOUT a ``parentPom``, we read its real ``.pom``,
   walk the ``<parent>`` chain, and -- if any ancestor is missing from this
   lockfile's prefetch set -- record the contiguous chain (immediate parent under
   ``parentPom``, deeper ancestors nested under ``parent``) with fetched sha256s,
   matching the schema maven-lockfile itself uses. hermeto dedups the pom forest,
   so recording it on one occurrence per GAV suffices. -> ``backfill_parent_poms``.

Run this after (re)generating the lockfiles with maven-lockfile. Idempotent.
Requires network access to the Red Hat Maven repo and the Maven Central mirror
(a dev-time regen step, NOT the hermetic build).
"""

import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

LOCAL_GROUP_ID = "dev.knative.eventing.kafka.broker"
# Fallback repo for productized (.redhat-*) artifacts when the parentPom URL
# cannot be used to derive the base.
REDHAT_GA_BASE = "https://maven.repository.redhat.com/ga/"
# Maven Central mirror used for non-productized artifacts (matches the
# ``resolved`` URLs and ``repositoryId`` maven-lockfile records for them).
CENTRAL_BASE = "https://maven-central.storage.googleapis.com/maven2/"
POM_NS = "{http://maven.apache.org/POM/4.0.0}"

# Keys under which hermeto's _extract_pom_chain follows a pom reference.
_PARENT_KEYS = ("parent", "parentPom", "pom")


def _hoist_boms(dst: dict, boms: list) -> None:
    """Merge ``boms`` into ``dst['boms']`` (dedup by GAV)."""
    existing = dst.get("boms", [])
    seen = {(b.get("groupId"), b.get("artifactId"), b.get("version")) for b in existing}
    for bom in boms or []:
        key = (bom.get("groupId"), bom.get("artifactId"), bom.get("version"))
        if key not in seen:
            existing.append(bom)
            seen.add(key)
    if existing:
        dst["boms"] = existing


def strip_local_parents(node, protect) -> bool:
    """Drop local reactor parent refs lacking ``resolved``; hoist their BOMs.

    Recurses through the whole document. ``protect`` is the module's own root
    pom dict, which must never be deleted (hermeto reads it as the root pom).
    """
    changed = False
    if isinstance(node, dict):
        for key in _PARENT_KEYS:
            child = node.get(key)
            if (
                isinstance(child, dict)
                and child is not protect
                and child.get("groupId") == LOCAL_GROUP_ID
                and "resolved" not in child
            ):
                _hoist_boms(node, child.get("boms"))
                del node[key]
                changed = True
        for value in node.values():
            changed |= strip_local_parents(value, protect)
    elif isinstance(node, list):
        for value in node:
            changed |= strip_local_parents(value, protect)
    return changed


def _iter_artifacts(node):
    """Yield every dict that looks like a Maven artifact (groupId + resolved)."""
    if isinstance(node, dict):
        if "groupId" in node and "resolved" in node:
            yield node
        for value in node.values():
            yield from _iter_artifacts(value)
    elif isinstance(node, list):
        for value in node:
            yield from _iter_artifacts(value)


def _repo_base(art: dict) -> tuple[str, str]:
    """Derive (base_url, repositoryId) from the artifact's own resolved parentPom."""
    parent = art.get("parentPom")
    if isinstance(parent, dict):
        pr = parent.get("resolved", "")
        gid, aid, ver = parent.get("groupId"), parent.get("artifactId"), parent.get("version")
        if pr and gid and aid and ver:
            suffix = f"{gid.replace('.', '/')}/{aid}/{ver}/{aid}-{ver}.pom"
            if pr.endswith(suffix):
                return pr[: -len(suffix)], (parent.get("repositoryId") or "redhat")
    if ".redhat-" in str(art.get("version", "")):
        return REDHAT_GA_BASE, "redhat"
    raise RuntimeError(
        f"cannot derive repo URL for {art.get('groupId')}:{art.get('artifactId')}:{art.get('version')}"
    )


def _sha256_of(url: str, cache: dict) -> str:
    if url in cache:
        return cache[url]
    req = urllib.request.Request(url, headers={"User-Agent": "hermeto-lockfile-fixup"})
    with urllib.request.urlopen(req) as resp:  # noqa: S310 (trusted Maven repo URL)
        digest = hashlib.sha256()
        for chunk in iter(lambda: resp.read(1 << 16), b""):
            digest.update(chunk)
    cache[url] = digest.hexdigest()
    return cache[url]


def backfill_external(data: dict, cache: dict) -> bool:
    """Fill resolved/checksum for external artifacts left empty by maven-lockfile."""
    changed = False
    for art in _iter_artifacts(data):
        if art.get("resolved") != "":
            continue
        if art.get("groupId") == LOCAL_GROUP_ID:
            continue  # reactor-local, built from source; removed by splice_local_deps
        gid, aid, ver = art["groupId"], art["artifactId"], art["version"]
        base, repo_id = _repo_base(art)
        url = f"{base}{gid.replace('.', '/')}/{aid}/{ver}/{aid}-{ver}.jar"
        art["resolved"] = url
        art["repositoryId"] = repo_id
        if not art.get("checksum"):
            art["checksum"] = _sha256_of(url, cache)
            art.setdefault("checksumAlgorithm", "SHA-256")
        changed = True
    return changed


def _splice(value):
    """Return ``(new_value, changed)``.

    Any reactor-local artifact dict with ``"resolved": ""`` that sits inside a
    list (``dependencies`` / ``children``) is removed and replaced by its own
    ``children`` -- which are themselves spliced first, so nested reactor-local
    nodes at any depth collapse away while every external descendant is kept.
    Dicts are recursed in place; lists are rebuilt.
    """
    if isinstance(value, dict):
        changed = False
        for key, child in list(value.items()):
            new_child, ch = _splice(child)
            if ch:
                value[key] = new_child
                changed = True
        return value, changed
    if isinstance(value, list):
        new_list = []
        changed = False
        for item in value:
            new_item, ch = _splice(item)  # splice the item's own children first
            changed |= ch
            if (
                isinstance(new_item, dict)
                and new_item.get("groupId") == LOCAL_GROUP_ID
                and new_item.get("resolved", None) == ""
            ):
                new_list.extend(new_item.get("children", []))
                changed = True
            else:
                new_list.append(new_item)
        return new_list, changed
    return value, False


def splice_local_deps(data: dict) -> bool:
    """Remove reactor-local ``resolved:""`` deps, hoisting their children."""
    _, changed = _splice(data)
    return changed


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "hermeto-lockfile-fixup"})
    with urllib.request.urlopen(req) as resp:  # noqa: S310 (trusted Maven repo URL)
        return resp.read()


def _pom_path(gid: str, aid: str, ver: str) -> str:
    return f"{gid.replace('.', '/')}/{aid}/{ver}/{aid}-{ver}.pom"


def _repo_id_for(url: str) -> str:
    return "redhat" if url.startswith(REDHAT_GA_BASE) else "google-maven-central"


def _fetch_pom(gid: str, aid: str, ver: str, cache: dict, exact_url: str = None):
    """Return ``(bytes, resolved_url)`` for a POM, or ``(None, None)`` if absent.

    Productized ``.redhat`` artifacts usually live on the Red Hat repo and the
    rest on the Central mirror, but parents can cross repos (a Red Hat artifact
    with a Central parent, or vice versa), so we try both. ``exact_url`` (a jar's
    sibling ``.pom``) is preferred when known.
    """
    key = ("pom", gid, aid, ver)
    if key in cache:
        return cache[key]
    ordered = [REDHAT_GA_BASE, CENTRAL_BASE]
    if ".redhat" not in ver:
        ordered.reverse()
    candidates = ([exact_url] if exact_url else []) + [b + _pom_path(gid, aid, ver) for b in ordered]
    for url in dict.fromkeys(candidates):  # de-dup, preserve order
        try:
            cache[key] = (_http_get(url), url)
            return cache[key]
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
    cache[key] = (None, None)
    return cache[key]


def _parent_gav(pom: bytes):
    """Return the ``(groupId, artifactId, version)`` of a POM's ``<parent>``."""
    try:
        root = ET.fromstring(pom)
    except ET.ParseError:
        return None
    parent = root.find(f"{POM_NS}parent")
    if parent is None:
        parent = root.find("parent")  # POMs without the 4.0.0 namespace
    if parent is None:
        return None

    def text(tag):
        el = parent.find(f"{POM_NS}{tag}")
        if el is None:
            el = parent.find(tag)
        return el.text.strip() if (el is not None and el.text) else None

    gid, aid, ver = text("groupId"), text("artifactId"), text("version")
    return (gid, aid, ver) if (gid and aid and ver) else None


def _prefetch_pom_gavs(data: dict) -> set:
    """GAVs of every POM already in this lockfile's prefetch contribution.

    hermeto fetches each jar's sibling ``.pom`` plus every explicitly-recorded
    ``.pom`` (parentPom / parent-dict / boms), so both cover a GAV's descriptor.
    """
    gavs = set()
    for art in _iter_artifacts(data):
        gid, aid, ver = art.get("groupId"), art.get("artifactId"), art.get("version")
        res = art.get("resolved") or ""
        if gid and aid and ver and (res.endswith(".pom") or res.endswith(".jar")):
            gavs.add((gid, aid, ver))
    return gavs


def _missing_parent_chain(node: dict, prefetch: set, cache: dict) -> list:
    """Real ``<parent>`` chain of ``node`` up to its deepest un-prefetched ancestor.

    Returns ``[(gav, url, pom_bytes), ...]`` from immediate parent to the deepest
    missing ancestor (empty if every ancestor is already prefetched). Any
    fully-prefetched tail beyond the last gap is trimmed -- we only add what is
    missing while keeping the chain contiguous from the artifact.
    """
    own = (node["groupId"], node["artifactId"], node["version"])
    pom, _ = _fetch_pom(*own, cache, exact_url=re.sub(r"\.jar$", ".pom", node["resolved"]))
    chain, seen = [], {own}
    while pom is not None:
        parent = _parent_gav(pom)
        if not parent or parent in seen:
            break
        seen.add(parent)
        pom, url = _fetch_pom(*parent, cache)
        if pom is None:  # parent POM in no known repo; cannot resolve further
            break
        chain.append((parent, url, pom))
    last_missing = max(
        (i for i, (gav, _u, _b) in enumerate(chain) if gav not in prefetch), default=-1
    )
    return chain[: last_missing + 1]


def _build_parent_pom(chain: list) -> dict:
    """Nest ``chain`` into a parentPom dict (deepest ancestor under ``parent``)."""
    node = None
    for (gid, aid, ver), url, pom in reversed(chain):
        entry = {
            "groupId": gid,
            "artifactId": aid,
            "version": ver,
            "resolved": url,
            "repositoryId": _repo_id_for(url),
            "checksumAlgorithm": "SHA-256",
            "checksum": hashlib.sha256(pom).hexdigest(),
        }
        if node is not None:
            entry["parent"] = node
        node = entry
    return node


def backfill_parent_poms(data: dict, cache: dict) -> bool:
    """Record Maven parent-POM chains hermeto would otherwise never prefetch."""
    changed = False
    prefetch = _prefetch_pom_gavs(data)
    done = set()
    for art in list(_iter_artifacts(data)):
        res = art.get("resolved") or ""
        if not res.endswith(".jar") or art.get("groupId") == LOCAL_GROUP_ID:
            continue
        if "parentPom" in art or not (art.get("artifactId") and art.get("version")):
            continue
        gav = (art["groupId"], art["artifactId"], art["version"])
        if gav in done:
            continue
        chain = _missing_parent_chain(art, prefetch, cache)
        if not chain:
            continue
        art["parentPom"] = _build_parent_pom(chain)
        done.add(gav)
        prefetch.update(g for g, _u, _b in chain)  # siblings sharing an ancestor now dedup
        changed = True
    return changed


def process(path: Path, cache: dict) -> bool:
    data = json.loads(path.read_text())
    root_pom = data.get("pom") if isinstance(data.get("pom"), dict) else None
    changed = strip_local_parents(data, root_pom)
    changed |= backfill_external(data, cache)
    changed |= splice_local_deps(data)
    changed |= backfill_parent_poms(data, cache)
    if changed:
        path.write_text(json.dumps(data, indent=2) + "\n")
    return changed


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parents[1]
    cache: dict = {}
    changed = 0
    for lf in sorted(root.rglob("lockfile.json")):
        if process(lf, cache):
            print(f"fixed: {lf}")
            changed += 1
        else:
            print(f"skip:  {lf}")
    print(f"\n{changed} lockfile(s) fixed for hermeto")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
