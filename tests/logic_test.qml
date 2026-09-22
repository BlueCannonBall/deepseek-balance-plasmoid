/*
    SPDX-FileCopyrightText: 2026
    SPDX-License-Identifier: GPL-2.0-or-later

    Exercises contents/ui/logic.js without a Plasma session.

    Run with:
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 qml6 tests/logic_test.qml
*/

import QtQuick
import "../package/contents/ui/logic.js" as Logic

Item {
    property int failures: 0

    function check(name, actual, expected) {
        if (actual === expected) {
            console.log("ok   " + name);
        } else {
            console.log("FAIL " + name + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
            failures += 1;
        }
    }

    Component.onCompleted: {
        const sample = {
            currency: "CNY",
            total_balance: "110.00",
            granted_balance: "10.00",
            topped_up_balance: "100.00"
        };
        const usd = {
            currency: "USD",
            total_balance: "5.50",
            granted_balance: "0.00",
            topped_up_balance: "5.50"
        };
        const okBody = JSON.stringify({
            is_available: true,
            balance_infos: [sample]
        });
        const noFundsBody = JSON.stringify({
            is_available: false,
            balance_infos: []
        });
        const errorBody = JSON.stringify({
            error: {
                message: "Authentication Fails, Your api key: ****test is invalid",
                type: "authentication_error"
            }
        });

        check("symbol CNY", Logic.currencySymbol("CNY"), "¥");
        check("symbol USD", Logic.currencySymbol("USD"), "$");
        check("symbol other", Logic.currencySymbol("EUR"), "EUR ");

        check("amount total", Logic.balanceAmount(sample, "total_balance"), 110);
        check("amount missing info", isNaN(Logic.balanceAmount(null, "total_balance")), true);
        check("amount missing field", isNaN(Logic.balanceAmount(sample, "nope")), true);

        check("format total", Logic.formatAmount(sample, "total_balance", false), "¥110.00");
        check("format with code", Logic.formatAmount(sample, "total_balance", true), "¥110.00 CNY");
        check("format usd", Logic.formatAmount(usd, "topped_up_balance", false), "$5.50");
        check("format null", Logic.formatAmount(null, "total_balance", false), "--");
        check("format missing field", Logic.formatAmount(sample, "nope", false), "--");

        check("select preferred", Logic.selectInfo([sample, usd], "USD").currency, "USD");
        check("select fallback", Logic.selectInfo([sample], "USD").currency, "CNY");
        check("select empty", Logic.selectInfo([], "CNY"), null);
        check("select null", Logic.selectInfo(null, "CNY"), null);

        const parsed = Logic.parseBalanceResponse(okBody);
        check("parse ok", parsed.ok, true);
        check("parse available", parsed.available, true);
        check("parse count", parsed.infos.length, 1);
        check("parse value", parsed.infos[0].total_balance, "110.00");

        const bad = Logic.parseBalanceResponse("this is not JSON");
        check("parse garbage ok", bad.ok, false);
        check("parse garbage infos", bad.infos.length, 0);

        check("parse no funds available", Logic.parseBalanceResponse(noFundsBody).available, false);

        check("error message", Logic.parseErrorResponse(errorBody), "Authentication Fails, Your api key: ****test is invalid");
        check("error garbage", Logic.parseErrorResponse("<html>"), "");

        check("formatValue plain", Logic.formatValue("USD", 5.5, false), "$5.50");
        check("formatValue code", Logic.formatValue("CNY", 110, true), "¥110.00 CNY");
        check("formatValue nan", Logic.formatValue("CNY", NaN, false), "--");

        const rich = { total_balance: "100.00", granted_balance: "0.00", topped_up_balance: "100.00" };
        check("spend none", Logic.spendBetween(rich, rich), 0);
        check("spend plain drop", Logic.spendBetween(rich, {
            total_balance: "90.00", granted_balance: "0.00", topped_up_balance: "100.00"
        }), 10);
        check("spend ignores top-up", Logic.spendBetween(rich, {
            total_balance: "120.00", granted_balance: "0.00", topped_up_balance: "120.00"
        }), 0);
        check("spend ignores new grant", Logic.spendBetween(rich, {
            total_balance: "110.00", granted_balance: "10.00", topped_up_balance: "100.00"
        }), 0);
        check("spend with top-up and usage", Logic.spendBetween(rich, {
            total_balance: "115.00", granted_balance: "0.00", topped_up_balance: "120.00"
        }), 5);
        check("spend null", Logic.spendBetween(null, rich), 0);

        const today = "2026-09-21";
        const yesterday = "2026-09-20";
        const blank = { day: "", currency: "", spent: 0, lastTotal: 0, lastGranted: 0, lastToppedUp: 0 };

        let state = Logic.accumulateSpend(blank, sample, today);
        check("accumulate first spent", state.spent, 0);
        check("accumulate first day", state.day, today);
        check("accumulate first currency", state.currency, "CNY");
        check("accumulate first lastTotal", state.lastTotal, 110);

        state = Logic.accumulateSpend(
            { day: today, currency: "CNY", spent: 2, lastTotal: 110, lastGranted: 10, lastToppedUp: 100 },
            { currency: "CNY", total_balance: "90.00", granted_balance: "10.00", topped_up_balance: "80.00" },
            today);
        check("accumulate same day", state.spent, 22);

        state = Logic.accumulateSpend(
            { day: yesterday, currency: "CNY", spent: 7, lastTotal: 110, lastGranted: 10, lastToppedUp: 100 },
            { currency: "CNY", total_balance: "80.00", granted_balance: "0.00", topped_up_balance: "80.00" },
            today);
        check("accumulate rollover resets", state.spent, 30);

        state = Logic.accumulateSpend(
            { day: today, currency: "CNY", spent: 7, lastTotal: 110, lastGranted: 10, lastToppedUp: 100 },
            { currency: "USD", total_balance: "5.00", granted_balance: "0.00", topped_up_balance: "5.00" },
            today);
        check("accumulate currency reset", state.spent, 0);
        check("accumulate currency code", state.currency, "USD");

        const guard = { day: today, currency: "CNY", spent: 5, lastTotal: 1, lastGranted: 1, lastToppedUp: 1 };
        check("accumulate ignores bad observation", Logic.accumulateSpend(guard, { currency: "CNY" }, today), guard);

        if (failures > 0) {
            console.log(failures + " test(s) failed");
            Qt.exit(1);
        }
        console.log("all tests passed");
        Qt.exit(0);
    }
}
