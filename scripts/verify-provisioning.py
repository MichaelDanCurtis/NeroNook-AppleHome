#!/usr/bin/env python3
"""Fail closed before producing an installable HomeKit release artifact."""
import datetime,pathlib,plistlib,subprocess,sys
app=pathlib.Path(sys.argv[1])
profile=next((p for p in [app/'Contents/embedded.provisionprofile',app/'embedded.mobileprovision',app/'Contents/embedded.mobileprovision'] if p.is_file()),None)
if profile is None:raise SystemExit('Missing Apple provisioning profile. Sign in to Xcode and provision this app.')
raw=subprocess.run(['/usr/bin/security','cms','-D','-i',str(profile)],capture_output=True,check=True).stdout
p=plistlib.loads(raw)
raw=subprocess.run(['/usr/bin/codesign','-d','--entitlements',':-',str(app)],capture_output=True,check=True).stdout
ent=plistlib.loads(raw);permitted=p['Entitlements']
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());bundle=info['CFBundleIdentifier']
identifier=ent.get('application-identifier',ent.get('com.apple.application-identifier',''))
allowed=permitted.get('application-identifier',permitted.get('com.apple.application-identifier',''))
if bundle!='cafe.nero.plugin.applehome' or identifier!=allowed or not identifier.endswith('.'+bundle):raise SystemExit('Signing profile does not match this Apple Home plugin identity.')
if ent.get('com.apple.developer.homekit') is not True or permitted.get('com.apple.developer.homekit') is not True:raise SystemExit('HomeKit entitlement is missing from the app or provisioning profile.')
if ent.get('com.apple.security.app-sandbox') is not True:raise SystemExit('Expected the independently sandboxed Catalyst app.')
expiry=p['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
if expiry<=datetime.datetime.now(datetime.timezone.utc):raise SystemExit('Provisioning profile has expired.')
print('PASS: exact app identity, HomeKit entitlement, sandbox and unexpired provisioning profile. System Home permission still requires live verification.')
