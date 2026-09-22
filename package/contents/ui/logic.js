/*
    SPDX-FileCopyrightText: 2026
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure helper functions for the DeepSeek balance applet. They are kept out of
    main.qml so that they can be exercised without a Plasma session; see
    tests/logic_test.qml.

    The reply schema is documented at
    https://api-docs.deepseek.com/api/get-user-balance

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

.pragma library

function currencySymbol(currency) {
    switch (currency) {
    case "CNY":
        return "¥";
    case "USD":
        return "$";
    default:
        return currency + " ";
    }
}

// Returns the requested balance as a number, or NaN when it is missing.
function balanceAmount(info, field) {
    if (!info) {
        return NaN;
    }
    return Number(info[field]);
}

function formatValue(currency, amount, showCurrencyCode) {
    if (isNaN(amount)) {
        return "--";
    }
    let text = currencySymbol(currency) + Number(amount).toFixed(2);
    if (showCurrencyCode) {
        text += " " + currency;
    }
    return text;
}

function formatAmount(info, field, showCurrencyCode) {
    if (!info) {
        return "--";
    }
    return formatValue(info.currency, balanceAmount(info, field), showCurrencyCode);
}

// Picks the preferred currency if it is present, otherwise the first entry.
function selectInfo(infos, preferredCurrency) {
    if (!infos) {
        return null;
    }
    for (let i = 0; i < infos.length; ++i) {
        if (infos[i].currency === preferredCurrency) {
            return infos[i];
        }
    }
    return infos.length > 0 ? infos[0] : null;
}

// The amount spent between two balance observations. An increase in the
// topped-up balance is money added by the user and an increase in the granted
// balance is new free credit; neither is spending, so both are added back.
// Clamped at zero so a mismatch can never show as negative spend.
function spendBetween(previous, current) {
    if (!previous || !current) {
        return 0;
    }
    const drop = Number(previous.total_balance) - Number(current.total_balance);
    const added = Math.max(0, Number(current.topped_up_balance) - Number(previous.topped_up_balance))
        + Math.max(0, Number(current.granted_balance) - Number(previous.granted_balance));
    if (isNaN(drop) || isNaN(added)) {
        return 0;
    }
    return Math.max(0, drop + added);
}

// Folds one observation into the running daily spend estimate.
//
// state is { day, currency, spent, lastTotal, lastGranted, lastToppedUp }, as
// persisted in the widget configuration. current is one balance_infos entry
// from DeepSeek. today is the local date as "yyyy-MM-dd".
//
// The estimate restarts when the local day or the currency changes, because the
// old figure cannot be compared with the new one. The first observation of a
// new day carries over the spend since the previous day's last observation, so
// usage between midnight and the first refresh is not lost.
//
// Caveats that the balance endpoint cannot resolve: expired granted credit is
// indistinguishable from spent credit, and anything that happens while the
// applet is not running is attributed to the day it is next seen.
function accumulateSpend(state, current, today) {
    if (!current
        || isNaN(Number(current.total_balance))
        || isNaN(Number(current.granted_balance))
        || isNaN(Number(current.topped_up_balance))) {
        return state;
    }

    const currency = current.currency;
    const initialized = state.day !== "" && state.currency === currency;
    const lastSeen = initialized ? {
        total_balance: state.lastTotal,
        granted_balance: state.lastGranted,
        topped_up_balance: state.lastToppedUp
    } : null;

    let spent;
    if (!initialized) {
        spent = 0;
    } else if (state.day !== today) {
        spent = spendBetween(lastSeen, current);
    } else {
        const prior = Number(state.spent);
        spent = (isNaN(prior) ? 0 : prior) + spendBetween(lastSeen, current);
    }

    return {
        day: today,
        currency: currency,
        spent: spent,
        lastTotal: Number(current.total_balance),
        lastGranted: Number(current.granted_balance),
        lastToppedUp: Number(current.topped_up_balance)
    };
}

// Returns { ok, available, infos, error }.
function parseBalanceResponse(responseText) {
    try {
        const payload = JSON.parse(responseText);
        return {
            ok: true,
            available: payload.is_available === true,
            infos: payload.balance_infos || [],
            error: ""
        };
    } catch (error) {
        return {
            ok: false,
            available: false,
            infos: [],
            error: String(error)
        };
    }
}

// Returns the human readable message from a DeepSeek error body, or "".
function parseErrorResponse(responseText) {
    try {
        return JSON.parse(responseText).error.message || "";
    } catch (error) {
        return "";
    }
}
