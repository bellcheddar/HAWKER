#!/usr/bin/env python3
"""
Fill in the App Store Connect listing for HAWKER.

Everything here is metadata: names, descriptions, categories, pricing and
screenshots. It never submits for review, and it never touches a build.

    set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a
    .venv/bin/python Tools/store_metadata.py all
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_api import call, token

BUNDLE_ID = "com.mdeller.hawker"
LOCALE = "en-US"

PRIVACY_POLICY_URL = "https://bellcheddar.github.io/HAWKER/privacy.html"
SUPPORT_URL = "https://github.com/bellcheddar/HAWKER"
MARKETING_URL = "https://marcdeller.com"

# Required before review. Year and holder, no (c) symbol: Apple adds it.
COPYRIGHT = "2026 Marc C. Deller"

PRIMARY_CATEGORY = "MEDICAL"
SECONDARY_CATEGORY = "REFERENCE"

# 30 characters.
SUBTITLE = "The drug graveyard, mined"

# 100 characters, comma separated, no spaces after commas (they count).
KEYWORDS = ("drug,clinical trial,repurposing,pharma,target,pocket,chembl,"
            "opentargets,pdb,discontinued")

# 170 characters. Changeable without a new build.
PROMOTIONAL_TEXT = (
    "Most shelved drugs did not fail on the biology. HAWKER separates death by "
    "business from death by science, and ranks what is worth a second look."
)

DESCRIPTION = """\
Thousands of clinical assets are dead. A large fraction died for reasons that had nothing to do with the biology: funding ran out, a trial could not recruit, two companies merged, a portfolio was reshuffled. The compound was fine. The pocket was fine.

HAWKER separates death by biology from death by business, anchors every dead asset onto its 3D structure and pocket, and ranks what deserves a second look.

WHERE THE DATA COMES FROM

Everything is pulled live from public APIs and nothing is hand curated: ChEMBL, ClinicalTrials.gov, Open Targets, UniChem, the RCSB Protein Data Bank, PubChem and openFDA. Cached on device so the app opens instantly and works offline.

HOW A CAUSE OF DEATH IS DECIDED

A deterministic lexicon runs over each trial's own stated reason for stopping, and every classification carries the exact substring that produced it, so you can audit it. Text the lexicon does not match falls through to an on-device nearest-neighbour vote against real sponsor statements, running on the Neural Engine, offline. It declines to answer rather than guess, and says which verdicts are inferred.

THE RESURRECTION SCORE

Four components, always shown separately, never collapsed into an unexplained number: how benign the death was, whether there is a structure to design against, whether the target has genetic evidence in a disease it was never tried in, and an estimate of how long ago composition-of-matter protection is likely to have lapsed.

SIX VIEWS

The Stall browses every dead asset. Post Mortem opens one, with its trial history, the sponsor's verbatim words, and a live 3D view of the ligand in its pocket. The Graveyard is the analytics: causes of death by year, by target class, by phase reached. The Second-hand Shelf holds those whose estimated patent horizon has passed. Pocket Reuse superposes every clinical ligand that ever bound a target, coloured by how each one died. The Overlook is the whole graveyard as a spatial console.

On iPhone, iPad, Mac, Apple Vision Pro and Apple Watch.

A NOTE ON THE PATENT ESTIMATE

The freedom-to-operate component is an estimate computed from public approval and registration dates. It is not a freedom-to-operate opinion and must not be relied on as legal guidance. The app labels it as an estimate everywhere it appears.

Built by Marc C. Deller, D.Phil.
"""

WHATS_NEW = """\
First release.

All 30,031 Pfam families, classified on device against an ESM-2 protein language model running on the Apple Neural Engine. Five views: a 3D map of the whole Pfam universe, a sequence oracle with calibrated confidence, a domain architecture explorer, a browser for the families with no known function, and an offline atlas you can search in plain English.

Universal across iPhone, iPad, Mac and Apple Vision Pro, with an Apple Watch companion.
"""


def app_id(auth: str) -> str:
    for a in call("GET", "/apps?limit=200", auth=auth)["data"]:
        if a["attributes"].get("bundleId") == BUNDLE_ID:
            return a["id"]
    sys.exit(f"No app record for {BUNDLE_ID}. Create it in App Store Connect first.")


def set_categories(auth: str, app: str) -> None:
    info = call("GET", f"/apps/{app}/appInfos", auth=auth)["data"][0]
    call("PATCH", f"/appInfos/{info['id']}", {
        "data": {
            "type": "appInfos",
            "id": info["id"],
            "relationships": {
                "primaryCategory": {
                    "data": {"type": "appCategories", "id": PRIMARY_CATEGORY}
                },
                "secondaryCategory": {
                    "data": {"type": "appCategories", "id": SECONDARY_CATEGORY}
                },
            },
        }
    }, auth=auth)
    print(f"  categories: {PRIMARY_CATEGORY} / {SECONDARY_CATEGORY}")


def set_app_info_localisation(auth: str, app: str) -> None:
    info = call("GET", f"/apps/{app}/appInfos", auth=auth)["data"][0]
    locs = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations", auth=auth)["data"]
    target = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    body = {
        "subtitle": SUBTITLE,
        "privacyPolicyUrl": PRIVACY_POLICY_URL,
    }
    if target:
        call("PATCH", f"/appInfoLocalizations/{target['id']}", {
            "data": {"type": "appInfoLocalizations", "id": target["id"],
                     "attributes": body}
        }, auth=auth)
        print(f"  subtitle + privacy policy set ({LOCALE})")
    else:
        call("POST", "/appInfoLocalizations", {
            "data": {"type": "appInfoLocalizations",
                     "attributes": {"locale": LOCALE, **body},
                     "relationships": {"appInfo": {
                         "data": {"type": "appInfos", "id": info["id"]}}}}
        }, auth=auth)
        print(f"  created localisation ({LOCALE})")


def versions(auth: str, app: str) -> list[dict]:
    return call("GET", f"/apps/{app}/appStoreVersions?limit=10", auth=auth)["data"]


def set_copyright(auth: str, app: str) -> None:
    """Copyright sits on the version, so a multiplatform record needs it thrice."""
    for version in versions(auth, app):
        call("PATCH", f"/appStoreVersions/{version['id']}", {
            "data": {"type": "appStoreVersions", "id": version["id"],
                     "attributes": {"copyright": COPYRIGHT}}
        }, auth=auth)
        print(f"  {version['attributes']['platform']}: copyright set")


def set_version_localisations(auth: str, app: str) -> None:
    for version in versions(auth, app):
        platform = version["attributes"].get("platform")
        locs = call("GET",
                    f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                    auth=auth)["data"]
        target = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
        body = {
            "description": DESCRIPTION,
            "keywords": KEYWORDS,
            "promotionalText": PROMOTIONAL_TEXT,
            "supportUrl": SUPPORT_URL,
            "marketingUrl": MARKETING_URL,
        }
        # "What's New" cannot be set on a first release: there is nothing to be
        # new against, and Apple rejects the attribute outright rather than
        # ignoring it. WHATS_NEW is kept for version 1.1 onwards.
        if (version["attributes"].get("versionString") or "1.0") != "1.0":
            body["whatsNew"] = WHATS_NEW
        if target:
            call("PATCH", f"/appStoreVersionLocalizations/{target['id']}", {
                "data": {"type": "appStoreVersionLocalizations",
                         "id": target["id"], "attributes": body}
            }, auth=auth)
            print(f"  {platform}: description, keywords and URLs set")
        else:
            call("POST", "/appStoreVersionLocalizations", {
                "data": {"type": "appStoreVersionLocalizations",
                         "attributes": {"locale": LOCALE, **body},
                         "relationships": {"appStoreVersion": {
                             "data": {"type": "appStoreVersions",
                                      "id": version["id"]}}}}
            }, auth=auth)
            print(f"  {platform}: created localisation")


def set_free(auth: str, app: str) -> None:
    """
    Free in every territory.

    The price schedule wants a base territory and a price point on the free
    tier, which is the one whose customerPrice is 0.0.
    """
    points = call("GET",
                  f"/apps/{app}/appPricePoints?filter[territory]=USA&limit=200",
                  auth=auth)["data"]
    free = next((p for p in points
                 if float(p["attributes"]["customerPrice"]) == 0.0), None)
    if not free:
        sys.exit("no free price point offered for this app")

    call("POST", "/appPriceSchedules", {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": app}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price}"}]},
            },
        },
        "included": [{
            "type": "appPrices",
            "id": "${price}",
            "relationships": {
                "appPricePoint": {"data": {"type": "appPricePoints",
                                           "id": free["id"]}}
            },
        }],
    }, auth=auth)
    print("  pricing: free in all territories")


def set_age_rating(auth: str, app: str) -> None:
    """
    A scientific reference tool with no objectionable content of any kind.
    Every field is declared explicitly rather than left to a default.
    """
    info = call("GET", f"/apps/{app}/appInfos", auth=auth)["data"][0]
    declaration = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration",
                       auth=auth)["data"]
    attributes = {
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE",
        "gamblingSimulated": "NONE",
        "horrorOrFearThemes": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "medicalOrTreatmentInformation": "NONE",
        "profanityOrCrudeHumor": "NONE",
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "gambling": False,
        # The structure viewer is a bundled Mol* build reading a cached file,
        # not a browser, so this is genuinely false.
        "unrestrictedWebAccess": False,
        "kidsAgeBand": None,
        # Everything below was discovered by asking: the API rejects the
        # request naming one missing attribute at a time, so the full set is
        # only visible by iterating. Types are not guessable either, and are
        # not consistent: ageAssurance is a BOOLEAN despite reading like an
        # enum, while gunsOrOtherWeapons is an enum despite sitting among the
        # booleans. Both were found by sending the wrong type and reading the
        # complaint.
        "ageAssurance": False,
        "messagingAndChat": False,
        "advertising": False,
        "healthOrWellnessTopics": False,
        "userGeneratedContent": False,
        "parentalControls": False,
        "lootBox": False,
        "gunsOrOtherWeapons": "NONE",
    }
    call("PATCH", f"/ageRatingDeclarations/{declaration['id']}", {
        "data": {"type": "ageRatingDeclarations", "id": declaration["id"],
                 "attributes": attributes}
    }, auth=auth)
    print("  age rating: no objectionable content declared")


# Which folder of captures goes to which display type, per platform version.
# APP_IPHONE_67 accepts the 6.9 inch 1320x2868 captures, and
# APP_IPAD_PRO_3GEN_129 accepts the 13 inch 2064x2752 ones: Apple did not add
# new display types for those sizes, which is not obvious from the names.
SCREENSHOT_PLAN = {
    # Both iPhone slots are filled. App Store Connect dims and locks whichever
    # size it decides to derive from another, so supplying only one leaves the
    # other showing as read-only. APP_IPHONE_65 at 1242x2688 is the pairing an
    # already-accepted app in this account uses, alongside the same iPad type.
    "IOS": [
        ("APP_IPHONE_67", "screenshots/iphone69"),
        ("APP_IPHONE_65", "screenshots/iphone65"),
        ("APP_IPAD_PRO_3GEN_129", "screenshots/ipad13"),
    ],
    "VISION_OS": [("APP_APPLE_VISION_PRO", "screenshots/visionos")],
    # An iOS binary that embeds a watch app must ship a watch screenshot, and
    # App Store Connect only says so at "Add for Review".
    "IOS_WATCH": [("APP_WATCH_SERIES_10", "screenshots/watch")],
    "MAC_OS": [("APP_DESKTOP", "screenshots/macos")],
}


def upload_screenshots(auth: str, app: str) -> None:
    import hashlib
    import urllib.request

    root = Path(__file__).resolve().parent.parent / "assets"

    for version in versions(auth, app):
        platform = version["attributes"].get("platform")
        plan = list(SCREENSHOT_PLAN.get(platform) or [])
        if platform == "IOS":
            plan += SCREENSHOT_PLAN.get("IOS_WATCH") or []
        if not plan:
            continue

        locs = call("GET",
                    f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                    auth=auth)["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
        if not loc:
            print(f"  {platform}: no {LOCALE} localisation")
            continue

        existing = call("GET",
                        f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                        auth=auth)["data"]
        by_type = {e["attributes"]["screenshotDisplayType"]: e["id"] for e in existing}

        for display_type, folder in plan:
            directory = root / folder
            images = sorted(directory.glob("*.png")) if directory.exists() else []
            if not images:
                print(f"  {platform} {display_type}: no captures in {folder}")
                continue

            set_id = by_type.get(display_type)
            if not set_id:
                created = call("POST", "/appScreenshotSets", {
                    "data": {
                        "type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": display_type},
                        "relationships": {"appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations",
                                     "id": loc["id"]}}},
                    }
                }, auth=auth)
                set_id = created["data"]["id"]

            have = call("GET", f"/appScreenshotSets/{set_id}/appScreenshots",
                        auth=auth)["data"]
            have_names = {h["attributes"].get("fileName") for h in have}

            for image in images:
                if image.name in have_names:
                    print(f"  {platform} {display_type}: {image.name} already there")
                    continue
                data = image.read_bytes()

                # Phase 1: reserve, and Apple replies with where to PUT it.
                reserved = call("POST", "/appScreenshots", {
                    "data": {
                        "type": "appScreenshots",
                        "attributes": {"fileSize": len(data), "fileName": image.name},
                        "relationships": {"appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": set_id}}},
                    }
                }, auth=auth)["data"]

                # Phase 2: run every upload operation. Large files come back as
                # several ranged PUTs, so this is a loop rather than one call.
                for op in reserved["attributes"]["uploadOperations"]:
                    chunk = data[op["offset"]:op["offset"] + op["length"]]
                    request = urllib.request.Request(
                        op["url"], method=op["method"], data=chunk)
                    for header in op.get("requestHeaders", []):
                        request.add_header(header["name"], header["value"])
                    urllib.request.urlopen(request, timeout=180).read()

                # Phase 3: commit with the checksum, or it stays in limbo and
                # never appears in the listing.
                call("PATCH", f"/appScreenshots/{reserved['id']}", {
                    "data": {
                        "type": "appScreenshots", "id": reserved["id"],
                        "attributes": {"uploaded": True,
                                       "sourceFileChecksum": hashlib.md5(data).hexdigest()},
                    }
                }, auth=auth)
                print(f"  {platform} {display_type}: uploaded {image.name}")

            order_screenshots(auth, set_id)


def order_screenshots(auth: str, set_id: str) -> None:
    """
    Tell the set what order its screenshots go in.

    Uploading is not enough. Until the set's `appScreenshots` relationship is
    PATCHed with an explicit ordering, App Store Connect renders the images
    greyed out and refuses to let you click them, even though the API reports
    every asset as COMPLETE with no errors and no warnings. Nothing in the
    upload response hints at this.
    """
    shots = call("GET", f"/appScreenshotSets/{set_id}/appScreenshots", auth=auth)["data"]
    if not shots:
        return
    ordered = sorted(shots, key=lambda s: s["attributes"].get("fileName") or "")
    call("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots", {
        "data": [{"type": "appScreenshots", "id": s["id"]} for s in ordered]
    }, auth=auth)
    print(f"    ordered {len(ordered)} screenshots")


EULA_TEXT = """\
PfamIE is free and open-source software, licensed under the MIT Licence.

Copyright (c) 2026 Marc C. Deller

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Source code: https://github.com/bellcheddar/PfamIE

BUNDLED THIRD-PARTY COMPONENTS

This app includes the ESM-2 protein language model (MIT, Meta Platforms), the all-MiniLM-L6-v2 sentence embedding model (Apache Licence 2.0, modified for Core ML), the Mol* structure viewer (MIT), and data derived from Pfam 38.2 (CC0 1.0 public domain dedication) and InterPro at EMBL-EBI. Full attribution is at https://github.com/bellcheddar/PfamIE/blob/main/THIRD-PARTY-NOTICES.md

SCIENTIFIC USE

PfamIE produces predictions, not assignments. Measured on 2,500 real UniProt proteins, its top answer is correct about 49% of the time, and every result states the measured accuracy of its confidence band. It is not a medical device and is not intended for diagnostic use.
"""


def set_eula(auth: str, app: str) -> None:
    """
    A custom licence agreement.

    Apple's standard EULA is the default and would be perfectly adequate, but
    this app is MIT-licensed open source that bundles four third-party
    components under three different licences, and the store listing is where
    a user is most likely to look for that.
    """
    territories = [t["id"] for t in
                   call("GET", "/territories?limit=200", auth=auth)["data"]]

    existing = call("GET", f"/apps/{app}/endUserLicenseAgreement", auth=auth).get("data")
    body_attributes = {"agreementText": EULA_TEXT}
    relationships = {
        "app": {"data": {"type": "apps", "id": app}},
        "territories": {"data": [{"type": "territories", "id": t}
                                 for t in territories]},
    }
    if existing:
        call("PATCH", f"/endUserLicenseAgreements/{existing['id']}", {
            "data": {"type": "endUserLicenseAgreements", "id": existing["id"],
                     "attributes": body_attributes,
                     "relationships": {"territories": relationships["territories"]}}
        }, auth=auth)
        print(f"  licence agreement updated ({len(territories)} territories)")
    else:
        call("POST", "/endUserLicenseAgreements", {
            "data": {"type": "endUserLicenseAgreements",
                     "attributes": body_attributes,
                     "relationships": relationships}
        }, auth=auth)
        print(f"  licence agreement set ({len(territories)} territories)")


def attach_builds(auth: str, app: str) -> None:
    """
    Attach each processed build to its platform's version.

    A build cannot be attached while Apple is still processing it: the PATCH
    returns 409. Processing takes ten to thirty minutes, so this is a separate,
    re-runnable step rather than part of the upload.
    """
    by_platform = {}
    for build in call("GET", f"/apps/{app}/builds?limit=20", auth=auth)["data"]:
        if build["attributes"].get("processingState") != "VALID":
            continue
        pre = call("GET", f"/builds/{build['id']}/preReleaseVersion",
                   auth=auth).get("data") or {}
        platform = (pre.get("attributes") or {}).get("platform")
        if platform:
            by_platform.setdefault(platform, build["id"])

    for version in versions(auth, app):
        platform = version["attributes"]["platform"]
        current = call("GET", f"/appStoreVersions/{version['id']}/build",
                       auth=auth).get("data")
        if current:
            print(f"  {platform}: already attached")
            continue
        build_id = by_platform.get(platform)
        if not build_id:
            print(f"  {platform}: no processed build yet")
            continue
        call("PATCH", f"/appStoreVersions/{version['id']}", {
            "data": {"type": "appStoreVersions", "id": version["id"],
                     "relationships": {"build": {"data": {"type": "builds",
                                                          "id": build_id}}}}
        }, auth=auth)
        print(f"  {platform}: attached")


def reorder_all_screenshots(auth: str, app: str) -> None:
    """Re-apply the display order to every existing set."""
    for version in versions(auth, app):
        platform = version["attributes"]["platform"]
        for loc in call("GET",
                        f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                        auth=auth)["data"]:
            for st in call("GET",
                           f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                           auth=auth)["data"]:
                print(f"  {platform} {st['attributes']['screenshotDisplayType']}:")
                order_screenshots(auth, st["id"])


# App Review contact. Reused across every platform version.
REVIEW_CONTACT = {
    "contactFirstName": "Marc",
    "contactLastName": "Deller",
    "contactPhone": "13023586093",
    "contactEmail": "marc@marcdeller.com",
    "demoAccountRequired": False,
}

REVIEW_NOTES = """\
HAWKER needs no account, no sign-in and no purchase. Everything is free and public.

WHAT TO EXPECT ON FIRST LAUNCH
The app fetches from public biomedical APIs (ChEMBL at EBI, ClinicalTrials.gov,
Open Targets, RCSB PDB, PubChem, openFDA). The first launch downloads and joins a
few thousand records and takes two to four minutes on a good connection, showing a
progress count the whole time. This is expected and is not a hang. Every later
launch reads a local cache and opens in under two seconds.

A SUGGESTED TWO-MINUTE PASS
1. Open the app and wait for "The Stall" to fill with cards.
2. Tap any card. That opens Post Mortem: four score bars, the trial history, and
   the sponsor's own verbatim reason for stopping with the matched words
   highlighted.
3. Scroll to the 3D panel and drag to rotate. Structures download from the RCSB
   Protein Data Bank, so this needs a network connection the first time.
4. Tap "The Graveyard" tab for the charts, then tap any bar to drill into a
   filtered list.
5. The "Method" button, present on every tab, prints the full classification
   lexicon, the thresholds and the record counts. Nothing in the app is a
   black box.

ON APPLE WATCH
The watch app shows the top 25 assets and syncs from the phone. If the phone app
has not completed its first fetch, the watch shows an explicit "waiting for
iPhone" state rather than an empty list.

A NOTE ON MEDICAL CLAIMS
HAWKER makes no diagnostic or treatment claim, gives no medical advice, and is
not for patient use. It is a literature and database browser for drug discovery
researchers over entirely public data. The "freedom to operate" figure is
explicitly labelled in the app as a crude estimate from public dates and not as
legal guidance.

PRIVACY
No data is collected. No analytics, no tracking, no account. The app makes
outbound requests only to the public scientific APIs listed above, and stores its
cache locally on device.
"""



def set_review_details(auth: str, app: str) -> None:
    """
    App Review contact information, per platform version.

    Required before submission and easy to miss, because App Store Connect
    lists it under the version rather than the app: a multiplatform app needs
    it filled in separately for each of iOS, macOS and visionOS.
    """
    for version in versions(auth, app):
        platform = version["attributes"]["platform"]
        existing = call("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail",
                        auth=auth).get("data")
        attributes = {**REVIEW_CONTACT, "notes": REVIEW_NOTES}
        if existing:
            call("PATCH", f"/appStoreReviewDetails/{existing['id']}", {
                "data": {"type": "appStoreReviewDetails", "id": existing["id"],
                         "attributes": attributes}
            }, auth=auth)
            print(f"  {platform}: review contact updated")
        else:
            call("POST", "/appStoreReviewDetails", {
                "data": {"type": "appStoreReviewDetails", "attributes": attributes,
                         "relationships": {"appStoreVersion": {
                             "data": {"type": "appStoreVersions", "id": version["id"]}}}}
            }, auth=auth)
            print(f"  {platform}: review contact created")


def set_content_rights(auth: str, app: str) -> None:
    call("PATCH", f"/apps/{app}", {
        "data": {"type": "apps", "id": app,
                 "attributes": {
                     "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}
    }, auth=auth)
    print("  content rights: no third-party content requiring rights")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "all"
    auth = token()
    app = app_id(auth)
    print(f"app {app} ({BUNDLE_ID})")

    steps = {
        "categories": set_categories,
        "appinfo": set_app_info_localisation,
        "versions": set_version_localisations,
        "copyright": set_copyright,
        "pricing": set_free,
        "agerating": set_age_rating,
        "rights": set_content_rights,
        "screenshots": upload_screenshots,
        "eula": set_eula,
        "attach-builds": attach_builds,
        "review": set_review_details,
        "reorder": reorder_all_screenshots,
    }
    if command == "all":
        # Not attach-builds: a build still processing returns 409, and that is
        # a normal state rather than a failure worth printing on every run.
        chosen = {k: v for k, v in steps.items() if k != "attach-builds"}
    else:
        chosen = {command: steps[command]}
    for name, fn in chosen.items():
        try:
            fn(auth, app)
        except Exception as error:
            print(f"  FAILED {name}: {str(error)[:400]}")
