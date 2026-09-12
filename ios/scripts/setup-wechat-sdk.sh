#!/bin/sh
set -eu
sdk_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_archive=$(mktemp -t zhouji-wechat-sdk)
trap 'rm -f "$sdk_archive"' EXIT HUP INT TERM
curl --fail --location --silent --show-error \
  https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK2.0.7_NoPay.zip \
  --output "$sdk_archive"
sdk_checksum=$(shasum -a 256 "$sdk_archive" | awk '{print $1}')
if [ "$sdk_checksum" != ce1cb4736d56adb9423561c40504f6ffdf841024dc2196bd38542228fbd7587d ]; then
  echo 'SDK checksum mismatch; nothing installed.' >&2
  exit 1
fi
mkdir -p "$sdk_root/Vendor"
unzip -qo "$sdk_archive" -d "$sdk_root/Vendor"
echo 'Official WeChat OpenSDK 2.0.7 NoPay installed in ignored Vendor directory.'
