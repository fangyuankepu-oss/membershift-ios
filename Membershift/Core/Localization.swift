import Foundation

/// App language. Skeleton ships Simplified Chinese (default) + English.
/// Android ships 7 languages; the remaining 5 (繁體中文 / Français /
/// Español / Italiano / فارسی) are a phase-2 addition — the table below
/// is the only place that needs new columns.
enum AppLanguage: String, CaseIterable {
    case zhHans = "zh-Hans"
    case en

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

enum L10n {
    private static let userDefaultsKey = "ms_lang"

    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let lang = AppLanguage(rawValue: raw) else { return .zhHans }
            return lang
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }

    /// Looks up `key` in the current language, falling back to Chinese,
    /// then to the key itself (never crashes on a missing key).
    static func string(_ key: String) -> String {
        strings[key]?[current] ?? strings[key]?[.zhHans] ?? key
    }

    private static let strings: [String: [AppLanguage: String]] = [
        "app_name": [
            .zhHans: "Membershift",
            .en: "Membershift",
        ],
        "login_title": [
            .zhHans: "会员积分系统",
            .en: "Membership Points System",
        ],
        "login_username": [
            .zhHans: "用户名",
            .en: "Username",
        ],
        "login_password": [
            .zhHans: "密码",
            .en: "Password",
        ],
        "login_button": [
            .zhHans: "登录",
            .en: "Log in",
        ],
        "login_error": [
            .zhHans: "用户名或密码错误",
            .en: "Wrong username or password",
        ],
        "login_hint": [
            .zhHans: "默认账号 admin / 123456",
            .en: "Default account admin / 123456",
        ],
        "login_hint2": [
            .zhHans: "登录后请在设置中修改密码",
            .en: "Please change the password in Settings after logging in",
        ],
        "login_language": [
            .zhHans: "语言",
            .en: "Language",
        ],
        "logout": [
            .zhHans: "退出登录",
            .en: "Log out",
        ],
        "db_error": [
            .zhHans: "数据库打开失败",
            .en: "Failed to open database",
        ],
        "nav_dashboard": [
            .zhHans: "仪表盘",
            .en: "Dashboard",
        ],
        "nav_stats": [
            .zhHans: "数据统计",
            .en: "Statistics",
        ],
        "nav_members": [
            .zhHans: "会员管理",
            .en: "Members",
        ],
        "nav_booking": [
            .zhHans: "预约",
            .en: "Booking",
        ],
        "nav_recharge": [
            .zhHans: "充值扣减",
            .en: "Recharge & Deduct",
        ],
        "nav_gifts": [
            .zhHans: "礼品兑换",
            .en: "Gifts",
        ],
        "nav_coupons": [
            .zhHans: "优惠券",
            .en: "Coupons",
        ],
        "nav_transactions": [
            .zhHans: "交易流水",
            .en: "Transactions",
        ],
        "nav_settings": [
            .zhHans: "系统设置",
            .en: "Settings",
        ],
        "page_wip": [
            .zhHans: "开发中",
            .en: "Coming soon",
        ],
        "page_wip_detail": [
            .zhHans: "该页面为骨架占位，第一阶段只验证导航与登录，功能在后续阶段接入。",
            .en: "This page is a skeleton placeholder. Phase 1 only verifies navigation and login; features arrive in later phases.",
        ],
        "dash_refresh": [
            .zhHans: "刷新",
            .en: "Refresh",
        ],
        "dash_members": [
            .zhHans: "会员总数",
            .en: "Total Members",
        ],
        "dash_today_sales": [
            .zhHans: "今日营业额",
            .en: "Today's Sales",
        ],
        "dash_month_sales": [
            .zhHans: "本月营业额",
            .en: "This Month's Sales",
        ],
        "dash_points_issued": [
            .zhHans: "累计发放积分",
            .en: "Points Issued (Total)",
        ],
        "dash_points_used": [
            .zhHans: "累计消耗积分",
            .en: "Points Used (Total)",
        ],
        "dash_balance_total": [
            .zhHans: "储值总余额",
            .en: "Total Stored Value",
        ],
        "dash_expiring_title": [
            .zhHans: "积分将过期提醒",
            .en: "Points Expiring Soon",
        ],
        "dash_expiring_none": [
            .zhHans: "暂无 30 天内到期的积分",
            .en: "No points expire in the next 30 days",
        ],
        "dash_expiring_fmt": [
            .zhHans: "%1$d 位会员 · %2$d 分将过期（最近 %3$@）",
            .en: "%1$d members · %2$d points expiring (soonest %3$@)",
        ],
        "dash_expiring_one": [
            .zhHans: "%1$d 位会员 · %2$d 分将过期（最近 %3$@）",
            .en: "%1$d member · %2$d points expiring (soonest %3$@)",
        ],
        "dash_chart_title": [
            .zhHans: "近 14 天营业额",
            .en: "Sales — Last 14 Days",
        ],
        "dash_chart_empty": [
            .zhHans: "近 14 天暂无营业额",
            .en: "No sales in the last 14 days",
        ],
        "dash_top_title": [
            .zhHans: "消费 TOP 5",
            .en: "Top 5 by Spending",
        ],
        "dash_top_empty": [
            .zhHans: "暂无消费记录",
            .en: "No spending records yet",
        ],
        "dash_birthday_title": [
            .zhHans: "未来 7 天生日",
            .en: "Birthdays in the Next 7 Days",
        ],
        "dash_birthday_none": [
            .zhHans: "未来 7 天没有会员生日",
            .en: "No member birthdays in the next 7 days",
        ],
        "dash_recent_title": [
            .zhHans: "最近流水",
            .en: "Recent Transactions",
        ],
        "dash_recent_empty": [
            .zhHans: "暂无流水",
            .en: "No transactions yet",
        ],
        "dash_tx_guest": [
            .zhHans: "散客",
            .en: "Walk-in",
        ],
        "mem_points_fmt": [
            .zhHans: "%1$d 分",
            .en: "%1$d points",
        ],
        "tx_checkout": [
            .zhHans: "消费结算",
            .en: "Checkout",
        ],
        "tx_earn": [
            .zhHans: "消费兑换积分",
            .en: "Earn Points",
        ],
        "tx_recharge": [
            .zhHans: "储值充值",
            .en: "Stored Value Top-Up",
        ],
        "tx_exchange": [
            .zhHans: "礼品兑换",
            .en: "Gift Redemption",
        ],
        "tx_adjust": [
            .zhHans: "积分调整",
            .en: "Points Adjustment",
        ],
        "tx_points_expire": [
            .zhHans: "积分过期",
            .en: "Points Expired",
        ],
        "tx_referral": [
            .zhHans: "转介绍奖励",
            .en: "Referral Reward",
        ],
        "tx_coupon_redeem": [
            .zhHans: "券核销",
            .en: "Coupon redeemed",
        ],
        "tx_unknown": [
            .zhHans: "其他",
            .en: "Other",
        ],
        "lic_wall_title": [
            .zhHans: "免费试用已到期",
            .en: "Free trial expired",
        ],
        "lic_wall_body": [
            .zhHans: "输入激活码即可继续使用，您的全部数据都完好保留。",
            .en: "Enter your activation code to continue. All your data is kept.",
        ],
        "lic_wall_code_placeholder": [
            .zhHans: "输入激活码",
            .en: "Enter activation code",
        ],
        "lic_wall_activate": [
            .zhHans: "激活",
            .en: "Activate",
        ],
        "lic_wall_note": [
            .zhHans: "激活码验证尚未接入（第一阶段占位）。",
            .en: "Activation-code verification is not wired up yet (phase 1 placeholder).",
        ],
    ]
}
