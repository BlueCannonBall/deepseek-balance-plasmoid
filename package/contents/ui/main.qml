/*
    SPDX-FileCopyrightText: 2026
    SPDX-License-Identifier: GPL-2.0-or-later

    Reads the balance of a DeepSeek API account from
    https://api.deepseek.com/user/balance and shows it on the desktop or in a
    panel. The reply schema is documented at
    https://api-docs.deepseek.com/api/get-user-balance and looks like:

        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "110.00",
                    "granted_balance": "10.00",
                    "topped_up_balance": "100.00"
                }
            ]
        }
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

PlasmoidItem {
    id: root

    readonly property string apiKey: (plasmoid.configuration.apiKey || "").trim()
    readonly property bool configured: apiKey.length > 0
    readonly property int requestTimeoutMs: 30000
    // DeepSeek's own docs only link to https://platform.deepseek.com/ ; the
    // /top_up route is not officially documented, but it is confirmed working.
    readonly property string topUpUrl: "https://platform.deepseek.com/top_up"

    property var balanceInfos: []
    property bool fundsAvailable: false
    property bool loading: false
    property var activeRequest: null
    property string lastError: ""
    property double lastUpdated: 0

    // The currency block to show in the panel: the preferred one if it is
    // present in the reply, otherwise the first one DeepSeek returned.
    readonly property var selectedInfo: Logic.selectInfo(balanceInfos, plasmoid.configuration.preferredCurrency)

    readonly property real selectedAmount: Logic.balanceAmount(selectedInfo, plasmoid.configuration.balanceField)

    readonly property bool lowBalance: {
        if (configured && lastError === "" && lastUpdated > 0 && !fundsAvailable) {
            return true;
        }
        return plasmoid.configuration.lowBalanceThreshold > 0
            && !isNaN(selectedAmount)
            && selectedAmount < plasmoid.configuration.lowBalanceThreshold;
    }

    Plasmoid.title: i18n("DeepSeek Balance")
    Plasmoid.status: lowBalance ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    toolTipMainText: root.panelText()
    toolTipTextFormat: Text.PlainText
    toolTipSubText: {
        if (root.lastError !== "") {
            return root.lastError;
        }
        if (!root.configured) {
            return i18n("No API key configured");
        }
        const lines = [];
        if (root.lastUpdated > 0) {
            lines.push(i18n("Spent today: %1", root.formatSpentToday()));
        }
        if (root.lastUpdated > 0 && !root.fundsAvailable) {
            lines.push(i18n("Insufficient balance"));
        }
        lines.push(root.updatedText());
        return lines.join("\n");
    }

    function formatAmountFor(info, field) {
        return Logic.formatAmount(info, field, plasmoid.configuration.showCurrencyCode);
    }

    function panelText() {
        if (lastError !== "") {
            return i18n("Error");
        }
        if (!selectedInfo) {
            return loading ? i18n("…") : i18n("--");
        }
        return formatAmountFor(selectedInfo, plasmoid.configuration.balanceField);
    }

    function updatedText() {
        if (lastUpdated === 0) {
            return loading ? i18n("Loading…") : i18n("Not updated yet");
        }
        return i18n("Updated at %1", Qt.formatTime(new Date(lastUpdated), "h:mm:ss AP"));
    }

    function trackSpend(info) {
        if (!info) {
            return;
        }
        const state = Logic.accumulateSpend({
            day: plasmoid.configuration.spendDay,
            currency: plasmoid.configuration.spendCurrency,
            spent: plasmoid.configuration.spentToday,
            lastTotal: plasmoid.configuration.spendLastTotal,
            lastGranted: plasmoid.configuration.spendLastGranted,
            lastToppedUp: plasmoid.configuration.spendLastToppedUp
        }, info, Qt.formatDate(new Date(), "yyyy-MM-dd"));

        plasmoid.configuration.spendDay = state.day;
        plasmoid.configuration.spendCurrency = state.currency;
        plasmoid.configuration.spentToday = state.spent;
        plasmoid.configuration.spendLastTotal = state.lastTotal;
        plasmoid.configuration.spendLastGranted = state.lastGranted;
        plasmoid.configuration.spendLastToppedUp = state.lastToppedUp;
    }

    function formatSpentToday() {
        const currency = plasmoid.configuration.spendCurrency;
        if (!currency) {
            return "--";
        }
        return Logic.formatValue(currency, plasmoid.configuration.spentToday, plasmoid.configuration.showCurrencyCode);
    }

    function refresh() {
        if (!configured) {
            lastError = i18n("No API key set. Open the widget settings and paste a DeepSeek API key.");
            return;
        }
        if (loading) {
            return;
        }

        loading = true;
        let timedOut = false;

        const xhr = new XMLHttpRequest();
        // Keep the request reachable: a purely local XMLHttpRequest can be
        // garbage collected mid-flight, after which no handler ever runs.
        activeRequest = xhr;

        xhr.open("GET", "https://api.deepseek.com/user/balance");
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = requestTimeoutMs;

        function settle() {
            requestWatchdog.stop();
            if (activeRequest === xhr) {
                activeRequest = null;
            }
            loading = false;
        }

        xhr.ontimeout = function () {
            timedOut = true;
        };

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            settle();

            if (xhr.status === 200) {
                const parsed = Logic.parseBalanceResponse(xhr.responseText);
                if (parsed.ok) {
                    root.balanceInfos = parsed.infos;
                    root.fundsAvailable = parsed.available;
                    root.lastError = "";
                    root.lastUpdated = Date.now();
                    root.trackSpend(Logic.selectInfo(parsed.infos, plasmoid.configuration.preferredCurrency));
                } else {
                    root.lastError = i18n("Could not parse the reply from DeepSeek: %1", parsed.error);
                }
                return;
            }

            if (xhr.status === 0) {
                root.lastError = timedOut
                    ? i18n("The request to DeepSeek timed out.")
                    : i18n("Could not contact api.deepseek.com.");
                return;
            }

            root.lastError = Logic.parseErrorResponse(xhr.responseText)
                || i18n("DeepSeek replied with HTTP status %1.", xhr.status);
        };

        // Qt's XMLHttpRequest timeout is not honoured for a stalled TCP
        // connect, so the watchdog is what actually ends such a request.
        requestWatchdog.restart();
        xhr.send();
    }

    compactRepresentation: Item {
        Layout.preferredWidth: compactRow.implicitWidth
        Layout.preferredHeight: compactRow.implicitHeight

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: root.lastError !== "" ? "dialog-warning" : "wallet-open"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: root.panelText()
                color: root.lowBalance ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: implicitHeight

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "wallet-open"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaExtras.Heading {
                level: 3
                text: i18n("DeepSeek Balance")
                Layout.fillWidth: true
            }

            PlasmaComponents.BusyIndicator {
                running: root.loading
                visible: root.loading
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
        }

        PlasmaComponents.Label {
            visible: !root.configured
            text: i18n("No API key set. Right-click this widget, choose “Configure…”, and paste a DeepSeek API key.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            visible: root.lastError !== ""
            text: root.lastError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        PlasmaComponents.Label {
            visible: root.configured && root.lastError === "" && root.lastUpdated > 0 && !root.fundsAvailable
            text: i18n("DeepSeek reports this account cannot make API calls: the balance is exhausted or unavailable.")
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Repeater {
            model: root.balanceInfos

            delegate: ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18nc("ISO currency code of the balance, e.g. CNY", "%1 account", modelData.currency)
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: root.formatAmountFor(modelData, "total_balance")
                        font.bold: true
                        color: root.lowBalance ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    }
                }

                GridLayout {
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: 0

                    PlasmaComponents.Label {
                        text: i18n("Topped-up:")
                        opacity: 0.7
                    }
                    PlasmaComponents.Label {
                        text: root.formatAmountFor(modelData, "topped_up_balance")
                    }
                    PlasmaComponents.Label {
                        text: i18n("Granted:")
                        opacity: 0.7
                    }
                    PlasmaComponents.Label {
                        text: root.formatAmountFor(modelData, "granted_balance")
                    }
                }
            }
        }

        PlasmaComponents.Label {
            visible: root.configured && root.lastError === "" && root.balanceInfos.length === 0
            text: root.loading ? i18n("Loading balance…") : i18n("DeepSeek returned no balance information.")
            opacity: 0.7
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.lastUpdated > 0

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Spent today:")
                opacity: 0.7
            }

            PlasmaComponents.Label {
                text: root.formatSpentToday()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.updatedText()
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }

            PlasmaComponents.Button {
                text: i18n("Top up")
                icon.name: "list-add"
                onClicked: Qt.openUrlExternally(root.topUpUrl)
            }

            PlasmaComponents.Button {
                text: i18n("Refresh")
                icon.name: "view-refresh"
                enabled: root.configured && !root.loading
                onClicked: root.refresh()
            }
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Top up DeepSeek balance")
            icon.name: "list-add"
            onTriggered: Qt.openUrlExternally(root.topUpUrl)
        },
        PlasmaCore.Action {
            text: i18n("Refresh DeepSeek balance")
            icon.name: "view-refresh"
            enabled: root.configured && !root.loading
            onTriggered: root.refresh()
        }
    ]

    Timer {
        id: requestWatchdog
        interval: root.requestTimeoutMs + 5000
        repeat: false

        onTriggered: {
            if (!root.loading) {
                return;
            }
            if (root.activeRequest) {
                root.activeRequest.abort();
                root.activeRequest = null;
            }
            root.loading = false;
            root.lastError = i18n("The request to DeepSeek timed out.");
        }
    }

    Timer {
        interval: Math.max(1, plasmoid.configuration.refreshIntervalMinutes) * 60 * 1000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: plasmoid.configuration

        function onApiKeyChanged() {
            root.balanceInfos = [];
            root.lastUpdated = 0;
            // A different key can mean a different account, so the spend
            // baseline from the old one must not be diffed against the new.
            plasmoid.configuration.spendDay = "";
            plasmoid.configuration.spendCurrency = "";
            plasmoid.configuration.spentToday = 0;
            root.refresh();
        }
    }
}
