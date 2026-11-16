"""Registers the app's bundle id with Apple (App Store Connect API) if it isn't there yet."""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # pyjwt

key_id, issuer, bundle = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], sys.argv[1]
key = open(os.path.expanduser(f"~/private_keys/AuthKey_{key_id}.p8")).read()
token = jwt.encode({"iss": issuer, "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})

def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(method, path, e.code, e.read().decode()[:600])
        raise

found = call("GET", "/v1/bundleIds?filter[identifier]=" + bundle)["data"]
if any(b["attributes"]["identifier"] == bundle for b in found):
    print("bundle id already registered:", bundle)
else:
    call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": bundle, "name": "COACH", "platform": "IOS"}}})
    print("registered bundle id:", bundle)
apps = call("GET", "/v1/apps?filter[bundleId]=" + bundle)["data"]
print("App Store Connect app:", apps[0]["attributes"]["name"] if apps else "NOT CREATED YET (create it in App Store Connect)")
