import os
import re
import sys
import base64

def main():
    keystore_base64 = os.environ.get('KEYSTORE_BASE64')
    keystore_password = os.environ.get('KEYSTORE_PASSWORD')
    key_alias = os.environ.get('KEY_ALIAS')
    key_password = os.environ.get('KEY_PASSWORD') or keystore_password

    if not keystore_base64:
        print("::error::KEYSTORE_BASE64 secret is missing or empty!")
        print("::error::Please add KEYSTORE_BASE64, KEYSTORE_PASSWORD, and KEY_ALIAS to GitHub Repository Secrets.")
        sys.exit(1)
    if not keystore_password:
        print("::error::KEYSTORE_PASSWORD secret is missing or empty!")
        sys.exit(1)
    if not key_alias:
        print("::error::KEY_ALIAS secret is missing or empty!")
        sys.exit(1)

    workspace = os.environ.get('GITHUB_WORKSPACE', os.getcwd())
    android_dir = os.path.join(workspace, 'android')
    app_dir = os.path.join(android_dir, 'app')
    os.makedirs(app_dir, exist_ok=True)

    # 1. Decode keystore file
    keystore_dest = os.path.join(app_dir, 'upload-keystore.jks')
    try:
        keystore_bytes = base64.b64decode(keystore_base64)
        with open(keystore_dest, 'wb') as f:
            f.write(keystore_bytes)
        print(f"Keystore decoded successfully to: {keystore_dest}")
    except Exception as e:
        print(f"::error::Failed to decode KEYSTORE_BASE64: {e}")
        sys.exit(1)

    # 2. Write key.properties
    key_properties_file = os.path.join(android_dir, 'key.properties')
    normalized_keystore_path = keystore_dest.replace('\\', '/')
    with open(key_properties_file, 'w', encoding='utf-8') as f:
        f.write(f"storePassword={keystore_password}\n")
        f.write(f"keyPassword={key_password}\n")
        f.write(f"keyAlias={key_alias}\n")
        f.write(f"storeFile={normalized_keystore_path}\n")
    print(f"Created: {key_properties_file}")

    # 3. Patch build.gradle.kts or build.gradle
    gradle_kts = os.path.join(app_dir, 'build.gradle.kts')
    gradle_groovy = os.path.join(app_dir, 'build.gradle')

    if os.path.exists(gradle_kts):
        with open(gradle_kts, 'r', encoding='utf-8') as f:
            content = f.read()

        if 'import java.util.Properties' not in content:
            content = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + content

        keystore_block = (
            "val keystoreProperties = Properties()\n"
            "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
            "android {\n"
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            keyAlias = keystoreProperties[\"keyAlias\"] as String?\n"
            "            keyPassword = keystoreProperties[\"keyPassword\"] as String?\n"
            "            storeFile = keystoreProperties[\"storeFile\"]?.let { file(it) }\n"
            "            storePassword = keystoreProperties[\"storePassword\"] as String?\n"
            "        }\n"
            "    }\n"
        )

        if 'val keystoreProperties' not in content:
            content = content.replace("android {", keystore_block, 1)

        content = re.sub(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = signingConfigs.getByName("release")',
            content
        )
        content = re.sub(
            r'signingConfig\s*=\s*signingConfigs\.debug',
            'signingConfig = signingConfigs.getByName("release")',
            content
        )

        with open(gradle_kts, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Updated android/app/build.gradle.kts with release signingConfig.")

    elif os.path.exists(gradle_groovy):
        with open(gradle_groovy, 'r', encoding='utf-8') as f:
            content = f.read()

        keystore_block = (
            "def keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
            "android {\n"
            "    signingConfigs {\n"
            "        release {\n"
            "            keyAlias keystoreProperties['keyAlias']\n"
            "            keyPassword keystoreProperties['keyPassword']\n"
            "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
            "            storePassword keystoreProperties['storePassword']\n"
            "        }\n"
            "    }\n"
        )

        if 'def keystoreProperties' not in content:
            content = content.replace("android {", keystore_block, 1)

        content = re.sub(
            r'signingConfig\s+signingConfigs\.debug',
            'signingConfig signingConfigs.release',
            content
        )

        with open(gradle_groovy, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Updated android/app/build.gradle with release signingConfig.")
    else:
        print("::error::Neither build.gradle.kts nor build.gradle found in android/app!")
        sys.exit(1)

    print("Keystore setup successfully completed!")

if __name__ == '__main__':
    main()

