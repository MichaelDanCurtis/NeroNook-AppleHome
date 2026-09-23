#!/usr/bin/env python3
"""Generate the small independent Xcode project; no registry dependency."""
import pathlib,hashlib,json
root=pathlib.Path(__file__).resolve().parents[1]
objects={}
def ID(s):return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
def obj(key, **value):objects[ID(key)]=value;return ID(key)
sourcefiles=[]
for path in sorted((root/'Sources').glob('*.swift')):
 ref=obj(path.name,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='Sources/'+path.name,sourceTree='<group>')
 sourcefiles.append(obj('build'+path.name,isa='PBXBuildFile',fileRef=ref))
manifest=obj('manifest',isa='PBXFileReference',lastKnownFileType='text.json',path='Resources/NookPlugin.json',sourceTree='<group>')
product=obj('product',isa='PBXFileReference',explicitFileType='wrapper.application',path='Apple Home Module.app',sourceTree='BUILT_PRODUCTS_DIR')
main=obj('main',isa='PBXGroup',children=[ID(p.name) for p in sorted((root/'Sources').glob('*.swift'))]+[manifest,product],sourceTree='<group>')
sources=obj('sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=sourcefiles,runOnlyForDeploymentPostprocessing=0)
resources=obj('resources',isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[obj('manifestBuild',isa='PBXBuildFile',fileRef=manifest)],runOnlyForDeploymentPostprocessing=0)
package=obj('sdkpackage',isa='XCLocalSwiftPackageReference',relativePath='Vendor/NookPluginSDK')
productdep=obj('sdkproduct',isa='XCSwiftPackageProductDependency',package=package,productName='NookPluginSDK')
frameworks=obj('frameworks',isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[obj('sdkbuild',isa='PBXBuildFile',productRef=productdep)],runOnlyForDeploymentPostprocessing=0)
settings=dict(PRODUCT_NAME='Apple Home Module',PRODUCT_BUNDLE_IDENTIFIER='cafe.nero.plugin.applehome',SWIFT_VERSION='5.0',SDKROOT='iphoneos',SUPPORTS_MACCATALYST='YES',DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER='NO',SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO',TARGETED_DEVICE_FAMILY='2',IPHONEOS_DEPLOYMENT_TARGET='17.0',MACOSX_DEPLOYMENT_TARGET='14.0',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='2GFVXB3249',CODE_SIGN_ENTITLEMENTS='Resources/AppleHome.entitlements',GENERATE_INFOPLIST_FILE='YES',INFOPLIST_KEY_NSHomeKitUsageDescription='Show your homes, rooms, accessories and scenes in the Apple Home module. This first version reads status only.',INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',INFOPLIST_KEY_UILaunchScreen_Generation='YES',INFOPLIST_KEY_LSApplicationCategoryType='public.app-category.lifestyle',CURRENT_PROJECT_VERSION='1',MARKETING_VERSION='0.1.0',ENABLE_HARDENED_RUNTIME='YES')
targetconfigs=[];projectconfigs=[]
for config in ['Debug','Release']:
 targetconfigs.append(obj('target'+config,isa='XCBuildConfiguration',name=config,buildSettings={**settings,**({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'} if config=='Debug' else {'SWIFT_OPTIMIZATION_LEVEL':'-O'})}))
 projectconfigs.append(obj('project'+config,isa='XCBuildConfiguration',name=config,buildSettings={'CLANG_ENABLE_MODULES':'YES'}))
targetlist=obj('targetconfig',isa='XCConfigurationList',buildConfigurations=targetconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
projectlist=obj('projectconfig',isa='XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=obj('target',isa='PBXNativeTarget',buildConfigurationList=targetlist,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[],name='AppleHome',packageProductDependencies=[productdep],productName='Apple Home Module',productReference=product,productType='com.apple.product-type.application')
project=obj('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2700','TargetAttributes':{target:{'CreatedOnToolsVersion':'27.0','SystemCapabilities':{'com.apple.HomeKit':{'enabled':1},'com.apple.Sandbox':{'enabled':1}}}}},buildConfigurationList=projectlist,compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=main,packageReferences=[package],projectDirPath='',projectRoot='',targets=[target])
def encode(v):
 if isinstance(v,dict):return '{\n'+'\n'.join(json.dumps(k)+' = '+encode(x)+';' for k,x in v.items())+'\n}'
 if isinstance(v,list):return '(\n'+',\n'.join(encode(x) for x in v)+'\n)'
 if isinstance(v,int):return str(v)
 return json.dumps(v)
path=root/'AppleHome.xcodeproj';path.mkdir(exist_ok=True)
(path/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project)))
