/*
    SPDX-FileCopyrightText: 2026
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configRoot

    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_refreshIntervalMinutes: refreshSpin.value
    property alias cfg_lowBalanceThreshold: thresholdSpin.value
    property alias cfg_showCurrencyCode: currencyCodeCheck.checked
    property string cfg_balanceField
    property string cfg_preferredCurrency

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("API key:")

            QQC.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                placeholderText: i18n("sk-…")
                echoMode: revealCheck.checked ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }

            QQC.CheckBox {
                id: revealCheck
                text: i18n("Show")
            }
        }

        QQC.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            text: i18n("The key is written in plain text to this widget's configuration file (~/.config/plasma-org.kde.plasma.desktop-appletsrc), which only your user can read but which is not encrypted. DeepSeek has no scoped keys, so anyone who reads it gets full API access to your account.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
        }

        QQC.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh every (minutes):")
            from: 1
            to: 1440
            stepSize: 1
            editable: true
        }

        QQC.SpinBox {
            id: thresholdSpin
            Kirigami.FormData.label: i18n("Warn below:")
            from: 0
            to: 100000
            stepSize: 1
            editable: true

            textFromValue: function (value) {
                return value === 0 ? i18n("Disabled") : String(value);
            }
            valueFromText: function (text) {
                return Number(text) || 0;
            }
        }

        QQC.ComboBox {
            id: balanceFieldCombo
            Kirigami.FormData.label: i18n("Panel shows:")
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    text: i18n("Total balance"),
                    value: "total_balance"
                },
                {
                    text: i18n("Topped-up balance"),
                    value: "topped_up_balance"
                },
                {
                    text: i18n("Granted balance"),
                    value: "granted_balance"
                }
            ]
            onActivated: configRoot.cfg_balanceField = currentValue

            Component.onCompleted: {
                for (let i = 0; i < model.length; ++i) {
                    if (model[i].value === configRoot.cfg_balanceField) {
                        currentIndex = i;
                        break;
                    }
                }
            }
        }

        QQC.ComboBox {
            id: currencyCombo
            Kirigami.FormData.label: i18n("Preferred currency:")
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    text: i18n("Automatic"),
                    value: ""
                },
                {
                    text: i18n("Chinese yuan (CNY)"),
                    value: "CNY"
                },
                {
                    text: i18n("US dollar (USD)"),
                    value: "USD"
                }
            ]
            onActivated: configRoot.cfg_preferredCurrency = currentValue

            Component.onCompleted: {
                for (let i = 0; i < model.length; ++i) {
                    if (model[i].value === configRoot.cfg_preferredCurrency) {
                        currentIndex = i;
                        break;
                    }
                }
            }
        }

        QQC.CheckBox {
            id: currencyCodeCheck
            Kirigami.FormData.label: i18n("Display:")
            text: i18n("Show the currency code (CNY/USD) after the amount")
        }
    }
}
