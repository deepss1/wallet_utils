// ignore_for_file: constant_identifier_names, non_constant_identifier_names, implementation_imports

import 'dart:typed_data';
import 'dart:convert';
import 'package:convert/convert.dart' show hex;
import 'package:bip39/bip39.dart' as bip39;
import 'package:wallet_utils/src/utilities/derivation.dart';
import 'package:wallet_utils/src/models/networks.dart' as network;
import 'package:wallet_utils/wallet_utils.dart' show Address, ECPair, KPWallet;

// https://github.com/RavenProject/Ravencoin/blob/master/src/assets/assets.cpp

class Validation {
  static const int maxFullNameLength = 32;
  static const int maxNameLength = 30; // Without $, !
  static const int maxChannelNameLength = 12;
  static const int maxVerifierString = 80;

  static final RegExp rootNameCharacters = RegExp(r'^[A-Z0-9._]{3,}$');
  static final RegExp subNameCharacters = RegExp(r'^[A-Z0-9._]+$');
  static final RegExp uniqueTagCharacters =
      RegExp(r'^[-A-Za-z0-9@$%&*()[\]{}_.?:]+$');
  static final RegExp msgChannelTagCharacters = RegExp(r'^[A-Za-z0-9_]+$');

  static final RegExp qualifierNameCharacters = RegExp(r'#[A-Z0-9._]{3,}$');
  static final RegExp subQualifierNameCharacters = RegExp(r'#[A-Z0-9._]+$');
  static final RegExp restrictedNameCharacters = RegExp(r'\$[A-Z0-9._]{3,}$');

  static final RegExp doublePunctuation = RegExp(r'^.*[._]{2,}.*$');
  static final RegExp leadingPunctuation = RegExp(r'^[._].*$');
  static final RegExp trailingPunctuation = RegExp(r'^.*[._]$');
  static final RegExp qualifierLeadingPunctuation = RegExp(r'^[#\$][._].*$');
  static final RegExp qualifingStringLogicNoParenthesis = RegExp(
      r'^((!?[A-Z0-9._]{3,})|((!?[A-Z0-9._]{3,}[|&])+!?[A-Z0-9._]{3,}))$');
  static final RegExp emptyParenthesis = RegExp(r'\(\)');
  static final RegExp childAssets = RegExp(r'#|/|~');

  static final RegExp ravenNames =
      RegExp(r'^RVN$|^RAVEN$|^RAVENCOIN$|^#RVN$|^#RAVEN$|^#RAVENCOIN$');

  /// todo identify a ipfs hash correctly...
// https://ethereum.stackexchange.com/questions/17094/how-to-store-ipfs-hash-using-bytes32/17112#17112
// looks like we just need to consider hex strings or something...
  static bool isIpfs(String x) => x.contains(RegExp(
      r'^Qm[1-9A-HJ-NP-Za-km-z]{44}$')); //|^b[A-Za-z2-7]{58}$|^B[A-Z2-7]{58}$|^z[1-9A-HJ-NP-Za-km-z]{48}$|^F[0-9A-F]{50}$'));
// We currently only support the base58 version of IPFS
// TODO: Validate and handle all kinds of IPFS validation

  static bool isAddressRVN(String x) =>
      Address.validateAddress(x, network.mainnet);
  static bool isAddressRVNt(String x) =>
      Address.validateAddress(x, network.testnet);
  static bool isTxIdRVN(String x) => x.contains(RegExp(r'^[0-9a-f]{64}$'));
// This is the raw hex that will be input into the chain as the associated IPFS
// Should be check as input as isTxIdRVN
//static bool isTxIdFlow(String x) => x.contains(RegExp(r'^5420[0-9a-f]{64}$'));

  static bool isRavencoinPath(String x) => x.contains(ravenNames);

  static bool isAdmin(String x) =>
      x.isNotEmpty &&
      x[x.length - 1] == '!' &&
      isAssetPath(x.substring(0, x.length - 1));

  static bool isAssetPath(String x) {
    if (x.isEmpty) {
      return false;
    }
    if (x.length > maxNameLength) {
      return false;
    }
    var lengthAdds = 0;
    if (x[0] == '\$') {
      lengthAdds += 1;
    }
    if (x[x.length - 1] == '!') {
      lengthAdds += 1;
    }
    if (x.contains(childAssets)) {
      lengthAdds += 1;
    }
    if (x.length > 30 + lengthAdds) {
      return false;
    }
    if (x[x.length - 1] == '!') {
      x = x.substring(0, x.length - 1);
    }
    if (x[0] == '#') {
      var qualifierSplits = x.split('/');
      return isQualifier(qualifierSplits[0]) &&
          qualifierSplits
              .sublist(1)
              .every((element) => isSubQualifier(element));
    } else if (x[0] == '\$') {
      return isRestricted(x);
    } else {
      var assetSplits = x.split('/');
      if (assetSplits.length > 1) {
        var lastAsset = assetSplits[assetSplits.length - 1];
        if (lastAsset.contains('#')) {
          var lastSplit = lastAsset.split('#');
          if (assetSplits.length > 1) {
            return isMainAsset(assetSplits[0]) &&
                assetSplits
                    .sublist(1, assetSplits.length - 1)
                    .every((element) => isSubAsset(element)) &&
                isSubAsset(lastSplit[0]) &&
                isNFT(lastSplit[1]);
          } else {
            return isMainAsset(lastSplit[0]) && isNFT(lastSplit[1]);
          }
        } else if (lastAsset.contains('~')) {
          var lastSplit = lastAsset.split('~');
          if (assetSplits.length > 1) {
            return isMainAsset(assetSplits[0]) &&
                assetSplits
                    .sublist(1, assetSplits.length - 1)
                    .every((element) => isSubAsset(element)) &&
                isSubAsset(lastSplit[0]) &&
                isChannel(lastSplit[1]);
          } else {
            return isMainAsset(lastSplit[0]) && isChannel(lastSplit[1]);
          }
        } else {
          return isMainAsset(assetSplits[0]) &&
              assetSplits.sublist(1).every((element) => isSubAsset(element));
        }
      }
      if (x.contains('#')) {
        var lastSplit = x.split('#');
        return isMainAsset(lastSplit[0]) && isNFT(lastSplit[1]);
      } else if (x.contains('~')) {
        var lastSplit = x.split('~');
        return isMainAsset(lastSplit[0]) && isChannel(lastSplit[1]);
      } else {
        return isMainAsset(x);
      }
    }
  }

// The following are only for their specific part in the asset
  static bool isMainAsset(String x) =>
      x.contains(rootNameCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(leadingPunctuation) &&
      !x.contains(trailingPunctuation) &&
      !x.contains(ravenNames);
  static bool isSubAsset(String x) =>
      x.contains(subNameCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(leadingPunctuation) &&
      !x.contains(trailingPunctuation);
  static bool isNFT(String x) => x.contains(uniqueTagCharacters);
  static bool isChannel(String x) =>
      x.length <= maxChannelNameLength &&
      x.contains(msgChannelTagCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(leadingPunctuation) &&
      !x.contains(trailingPunctuation);
  static bool isQualifier(String x) =>
      x.contains(qualifierNameCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(qualifierLeadingPunctuation) &&
      !x.contains(trailingPunctuation) &&
      !x.contains(ravenNames);
  static bool isSubQualifier(String x) =>
      x.contains(subQualifierNameCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(leadingPunctuation) &&
      !x.contains(trailingPunctuation);

  static bool isQualifierString(String x) =>
      x == 'true' ||
      (x.length <= maxVerifierString &&
          x
              .replaceAll(RegExp(r'\s+'), '')
              .replaceAll(RegExp(r'[\(\)]'), '')
              .contains(qualifingStringLogicNoParenthesis) &&
          !x.replaceAll(RegExp(r'\s+'), '').contains(emptyParenthesis) &&
          x.replaceAll(RegExp(r'\s+'), '').split('').fold(0,
                  (num previousValue, element) {
                if (element == '(') {
                  return previousValue + 1;
                } else if (element == ')') {
                  if (previousValue == 0) {
                    // End parenthsis with no beginning
                    return 50000;
                  }
                  return previousValue - 1;
                }
                return previousValue;
              }) ==
              0 &&
          !x.contains(doublePunctuation) &&
          !x.contains(qualifierLeadingPunctuation) &&
          !x.contains(trailingPunctuation) &&
          !x.contains(ravenNames) &&
          x.replaceAll(RegExp(r'[\(\)|&!]'), ' ').split(' ').every(
              (element) => element.isEmpty ? true : isQualifier('#$element')));
  static bool isRestricted(String x) =>
      x.contains(restrictedNameCharacters) &&
      !x.contains(doublePunctuation) &&
      !x.contains(leadingPunctuation) &&
      !x.contains(trailingPunctuation) &&
      !x.contains(ravenNames);
// static bool isVote(String x) => x.contains(RegExp(r'^$')); // Unused
  static bool isMemo(String x) => utf8.encode(x).length <= 80;
  static bool isAssetData(String x) => isIpfs(x) || isTxIdRVN(x);
  static bool isRVNAmount(num x) => x <= 21000000000 && x > 0;

  static bool isMnemonic(String x) =>
      bip39.validateMnemonic(x /*.toLowerCase()*/);
  static bool isWIF(String x, {bool mainnet = true}) {
    try {
      KPWallet.fromWIF(x, mainnet ? network.mainnet : network.testnet);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isPrivateKey(String x) {
    try {
      ECPair.fromPrivateKey(Uint8List.fromList(hex.decode(x))).toWIF();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isPublicKey(String x, {bool mainnet = true}) =>
      x.length == 130 || x.length == 66;

  static bool isPublicKeyAddress(String x, {bool mainnet = true}) =>
      mainnet ? isAddressRVN(x) : isAddressRVNt(x);

  static bool isDerivationPath(
    String x, {
    bool? ravencoin,
    bool? mainnet,
    bool? receive,
  }) {
    var split = x.split('/');
    var validated = split.length == 6 && split.first == 'm';
    if (ravencoin != null && ravencoin) {
      if (ravencoin) {
        validated =
            validated && split[1] == Derivation.ravencoinNumber.toString();
      } else {
        validated =
            validated && split[1] == Derivation.ravencoinNumber.toString();
      }
    }
    if (mainnet != null) {
      validated =
          validated && split[2] == Derivation.mainnetNumber(mainnet).toString();
    }
    if (receive != null) {
      validated =
          validated && split[4] == Derivation.receiveNumber(receive).toString();
    }
    return validated;
  }
}
