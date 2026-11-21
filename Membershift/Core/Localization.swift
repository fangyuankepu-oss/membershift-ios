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
            .zhHans: "%1$d 位会员 · %2$d 分将过期\n最近到期：%3$@",
            .en: "%1$d members · %2$d points expiring\nSoonest expiry: %3$@",
        ],
        "dash_expiring_one": [
            .zhHans: "%1$d 位会员 · %2$d 分将过期\n最近到期：%3$@",
            .en: "%1$d member · %2$d points expiring\nSoonest expiry: %3$@",
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
        // MARK: - Statistics (mirrors Android StatisticsPage / strings.xml)
        "stats_range_today": [
            .zhHans: "今天",
            .en: "Today",
        ],
        "stats_range_week": [
            .zhHans: "本周",
            .en: "Week",
        ],
        "stats_range_month": [
            .zhHans: "本月",
            .en: "Month",
        ],
        "stats_range_30": [
            .zhHans: "近 30 天",
            .en: "30 Days",
        ],
        "stats_range_custom": [
            .zhHans: "自定义",
            .en: "Custom",
        ],
        "stats_custom_from": [
            .zhHans: "开始日期",
            .en: "Start Date",
        ],
        "stats_custom_to": [
            .zhHans: "结束日期",
            .en: "End Date",
        ],
        "stats_total_sales": [
            .zhHans: "消费总额",
            .en: "Total Sales",
        ],
        "stats_total_recharge": [
            .zhHans: "充值总额",
            .en: "Total Top-Ups",
        ],
        "stats_new_members": [
            .zhHans: "新增会员",
            .en: "New Members",
        ],
        "stats_points_redeemed": [
            .zhHans: "积分兑换",
            .en: "Points Redeemed",
        ],
        "stats_vs_prev": [
            .zhHans: "较上周期 %1$@",
            .en: "%1$@ vs previous period",
        ],
        "stats_kpi_orders": [
            .zhHans: "订单数",
            .en: "Orders",
        ],
        "stats_kpi_active": [
            .zhHans: "活跃会员",
            .en: "Active Members",
        ],
        "stats_kpi_repeat": [
            .zhHans: "复购率",
            .en: "Repurchase Rate",
        ],
        "stats_kpi_redeem_rate": [
            .zhHans: "积分兑换率",
            .en: "Points Redemption Rate",
        ],
        "stats_kpi_avg": [
            .zhHans: "客单价",
            .en: "Average Order",
        ],
        "stats_trend_title": [
            .zhHans: "消费趋势",
            .en: "Consumption Trend",
        ],
        "stats_hours_title": [
            .zhHans: "时段分布",
            .en: "Sales by Time Slot",
        ],
        "stats_tier_title": [
            .zhHans: "等级分析",
            .en: "Tier Analysis",
        ],
        "stats_pay_title": [
            .zhHans: "支付方式",
            .en: "Payment Methods",
        ],
        "stats_coupon_title": [
            .zhHans: "优惠券",
            .en: "Coupons",
        ],
        "stats_gift_title": [
            .zhHans: "礼品兑换 Top 5",
            .en: "Top 5 Gift Redemptions",
        ],
        "stats_daily_title": [
            .zhHans: "每日明细",
            .en: "Daily Details",
        ],
        "stats_coupon_issued": [
            .zhHans: "发放 %1$d 张",
            .en: "%1$d issued",
        ],
        "stats_coupon_used": [
            .zhHans: "使用 %1$d 张",
            .en: "%1$d used",
        ],
        "stats_coupon_rate": [
            .zhHans: "使用率 %1$@",
            .en: "Usage rate %1$@",
        ],
        "stats_empty": [
            .zhHans: "暂无数据",
            .en: "No data",
        ],
        "stats_daily_col_date": [
            .zhHans: "日期",
            .en: "Date",
        ],
        "stats_daily_col_new": [
            .zhHans: "新增",
            .en: "New",
        ],
        "stats_daily_col_sales": [
            .zhHans: "消费",
            .en: "Purchase",
        ],
        "stats_daily_col_recharge": [
            .zhHans: "充值",
            .en: "Top-Ups",
        ],
        "stats_daily_col_issued": [
            .zhHans: "发分",
            .en: "Issued",
        ],
        "stats_daily_col_redeemed": [
            .zhHans: "兑分",
            .en: "Redeemed",
        ],
        "stats_daily_col_active": [
            .zhHans: "活跃",
            .en: "Active",
        ],
        "stats_tier_right_fmt": [
            .zhHans: "%1$d 人 · 累计消费 %2$@",
            .en: "%1$d members · Total spent %2$@",
        ],
        "stats_hour_fmt": [
            .zhHans: "%1$d–%2$d",
            .en: "%1$d–%2$d",
        ],
        "stats_gift_right_fmt": [
            .zhHans: "%1$d 次",
            .en: "%1$d times",
        ],
        "stats_count_fmt": [
            .zhHans: "%1$d 笔 · %2$@",
            .en: "%1$d transactions · %2$@",
        ],
        "stats_page_fmt": [
            .zhHans: "第 %1$d/%2$d 页",
            .en: "Page %1$d/%2$d",
        ],
        "stats_prev": [
            .zhHans: "上一页",
            .en: "Previous",
        ],
        "stats_next": [
            .zhHans: "下一页",
            .en: "Next",
        ],
        "pay_cash": [
            .zhHans: "现金",
            .en: "Cash",
        ],
        "pay_wechat": [
            .zhHans: "微信",
            .en: "WeChat Pay",
        ],
        "pay_alipay": [
            .zhHans: "支付宝",
            .en: "Alipay",
        ],
        "pay_card": [
            .zhHans: "银行卡",
            .en: "Bank Card",
        ],
        "pay_balance": [
            .zhHans: "储值余额",
            .en: "Stored Value",
        ],
        "pay_other": [
            .zhHans: "其他",
            .en: "Other",
        ],
        // MARK: - Members (mirrors Android MembersPage / strings.xml)
        "mem_search_hint": [
            .zhHans: "搜索姓名 / 手机号",
            .en: "Search name / phone",
        ],
        "mem_add": [
            .zhHans: "新增会员",
            .en: "Add Member",
        ],
        "mem_segment_all": [
            .zhHans: "全部",
            .en: "All",
        ],
        "mem_segment_new": [
            .zhHans: "新客",
            .en: "New Members",
        ],
        "mem_segment_dormant": [
            .zhHans: "沉睡会员",
            .en: "Dormant Members",
        ],
        "mem_segment_vip": [
            .zhHans: "高价值会员",
            .en: "High-Value Members",
        ],
        "mem_segment_expiring": [
            .zhHans: "积分将过期",
            .en: "Points Expiring",
        ],
        "mem_segment_count_fmt": [
            .zhHans: "%1$@（%2$d）",
            .en: "%1$@ (%2$d)",
        ],
        "mem_tag_all": [
            .zhHans: "全部标签",
            .en: "All Tags",
        ],
        "mem_empty": [
            .zhHans: "暂无会员",
            .en: "No members yet",
        ],
        "mem_expiring_badge": [
            .zhHans: "将过期",
            .en: "Expiring Soon",
        ],
        "mem_delete_confirm": [
            .zhHans: "确定删除会员 %1$@ 吗？相关券、积分台账、标签将一并删除。",
            .en: "Delete member %1$@? Related coupons, points ledger and tags will be deleted too.",
        ],
        "mem_deleted": [
            .zhHans: "会员已删除",
            .en: "Member deleted",
        ],
        "mem_detail_title": [
            .zhHans: "会员详情",
            .en: "Member Details",
        ],
        "mem_form_title_add": [
            .zhHans: "新增会员",
            .en: "Add Member",
        ],
        "mem_form_title_edit": [
            .zhHans: "编辑会员",
            .en: "Edit Member",
        ],
        "mem_name": [
            .zhHans: "姓名",
            .en: "Name",
        ],
        "mem_phone": [
            .zhHans: "手机号",
            .en: "Phone",
        ],
        "mem_email": [
            .zhHans: "邮箱（选填）",
            .en: "Email (optional)",
        ],
        "mem_pin": [
            .zhHans: "会员密码",
            .en: "Member PIN",
        ],
        "mem_pin_hint": [
            .zhHans: "4 位数字，选填",
            .en: "4 digits, optional",
        ],
        "mem_pin_hint_edit": [
            .zhHans: "留空不改",
            .en: "Leave blank to keep",
        ],
        "mem_pin_err": [
            .zhHans: "密码需为 4 位数字",
            .en: "PIN must be 4 digits",
        ],
        "mem_pin_clear": [
            .zhHans: "清除会员密码",
            .en: "Clear member PIN",
        ],
        "mem_pin_set": [
            .zhHans: "已设置密码",
            .en: "PIN set",
        ],
        "mem_pin_unset": [
            .zhHans: "未设置密码",
            .en: "No PIN set",
        ],
        "mem_gender": [
            .zhHans: "性别",
            .en: "Gender",
        ],
        "mem_gender_male": [
            .zhHans: "男",
            .en: "Male",
        ],
        "mem_gender_female": [
            .zhHans: "女",
            .en: "Female",
        ],
        "mem_gender_secret": [
            .zhHans: "保密",
            .en: "Prefer not to say",
        ],
        "mem_birthday": [
            .zhHans: "生日",
            .en: "Birthday",
        ],
        "mem_birthday_none": [
            .zhHans: "未设置",
            .en: "Not set",
        ],
        "mem_referrer": [
            .zhHans: "推荐人",
            .en: "Referrer",
        ],
        "mem_referrer_none": [
            .zhHans: "无",
            .en: "None",
        ],
        "mem_referrer_search": [
            .zhHans: "搜索推荐人",
            .en: "Search referrer",
        ],
        "mem_referrer_pick": [
            .zhHans: "选择推荐人",
            .en: "Choose referrer",
        ],
        "mem_note": [
            .zhHans: "备注",
            .en: "Note",
        ],
        "mem_save": [
            .zhHans: "保存",
            .en: "Save",
        ],
        "mem_cancel": [
            .zhHans: "取消",
            .en: "Cancel",
        ],
        "mem_err_name": [
            .zhHans: "请输入姓名",
            .en: "Please enter a name",
        ],
        "mem_err_phone": [
            .zhHans: "请输入手机号",
            .en: "Please enter a phone number",
        ],
        "mem_err_phone_dup": [
            .zhHans: "该手机号已被使用",
            .en: "This phone number is already in use",
        ],
        "mem_err_email": [
            .zhHans: "邮箱格式不正确",
            .en: "Invalid email address",
        ],
        "mem_saved": [
            .zhHans: "已保存",
            .en: "Saved",
        ],
        "mem_tier_progress": [
            .zhHans: "距 %1$@ 还差 %2$@",
            .en: "%1$@: %2$@ to go",
        ],
        "mem_tier_top": [
            .zhHans: "已是最高等级",
            .en: "Already at the highest tier",
        ],
        "mem_expiring_points": [
            .zhHans: "%1$d 分将于 %2$@ 前到期",
            .en: "%1$d points expire before %2$@",
        ],
        "mem_no_expiring": [
            .zhHans: "无 30 天内到期的积分",
            .en: "No points expire in the next 30 days",
        ],
        "mem_visits": [
            .zhHans: "到店 %1$d 次",
            .en: "%1$d visits",
        ],
        "mem_avg_order": [
            .zhHans: "平均客单价 %1$@",
            .en: "Avg. order %1$@",
        ],
        "mem_pref_cat": [
            .zhHans: "偏好品类",
            .en: "Preferred Categories",
        ],
        "mem_pref_product": [
            .zhHans: "偏好商品",
            .en: "Preferred Products",
        ],
        "mem_tags": [
            .zhHans: "标签",
            .en: "Tags",
        ],
        "mem_add_tag": [
            .zhHans: "添加标签",
            .en: "Add Tag",
        ],
        "mem_tag_hint": [
            .zhHans: "输入标签",
            .en: "Enter a tag",
        ],
        "mem_referrer_info": [
            .zhHans: "推荐人：%1$@",
            .en: "Referred by: %1$@",
        ],
        "mem_referred_count": [
            .zhHans: "已推荐 %1$d 人",
            .en: "Referred %1$d members",
        ],
        "mem_reward_pending": [
            .zhHans: "待首单发放",
            .en: "Pending first order",
        ],
        "mem_reward_done": [
            .zhHans: "已发放",
            .en: "Issued",
        ],
        "mem_coupons": [
            .zhHans: "持有优惠券",
            .en: "Coupons Held",
        ],
        "mem_recent_tx": [
            .zhHans: "最近流水",
            .en: "Recent Transactions",
        ],
        "mem_delete": [
            .zhHans: "删除",
            .en: "Delete",
        ],
        "mem_edit": [
            .zhHans: "编辑",
            .en: "Edit",
        ],
        "mem_close": [
            .zhHans: "关闭",
            .en: "Close",
        ],
        "mem_no_coupons": [
            .zhHans: "暂无优惠券",
            .en: "No coupons",
        ],
        "mem_no_tx": [
            .zhHans: "暂无流水",
            .en: "No transactions",
        ],
        "mem_no_tags": [
            .zhHans: "暂无标签",
            .en: "No tags yet",
        ],
        "mem_points_label": [
            .zhHans: "积分",
            .en: "Points",
        ],
        "mem_balance_label": [
            .zhHans: "储值余额",
            .en: "Stored Value Balance",
        ],
        "mem_total_spent_label": [
            .zhHans: "累计消费",
            .en: "Total Spent",
        ],
        "mem_phone_label": [
            .zhHans: "手机号",
            .en: "Phone",
        ],
        "mem_birthday_label": [
            .zhHans: "生日",
            .en: "Birthday",
        ],
        "mem_gender_label": [
            .zhHans: "性别",
            .en: "Gender",
        ],
        "mem_note_label": [
            .zhHans: "备注",
            .en: "Note",
        ],
        "mem_level_label": [
            .zhHans: "等级",
            .en: "Tier",
        ],
        "mem_discount_none": [
            .zhHans: "不打折",
            .en: "No discount",
        ],
        "mem_discount_fmt": [
            .zhHans: "%1$@折",
            .en: "%1$@/10 price",
        ],
        "mem_multiplier_fmt": [
            .zhHans: "积分 ×%1$@",
            .en: "Points ×%1$@",
        ],
        "mem_coupon_unused": [
            .zhHans: "未用",
            .en: "Unused",
        ],
        "mem_coupon_used": [
            .zhHans: "已用",
            .en: "Used",
        ],
        "mem_coupon_expired": [
            .zhHans: "已过期",
            .en: "Expired",
        ],
        "mem_coupon_fmt": [
            .zhHans: "%1$@ · %2$@ · 有效期至 %3$@",
            .en: "%1$@ · %2$@ · Valid until %3$@",
        ],
        "auth_pw_title": [
            .zhHans: "请输入密码确认",
            .en: "Enter password to confirm",
        ],
        "auth_pw_hint": [
            .zhHans: "登录密码",
            .en: "Login password",
        ],
        "auth_pw_wrong": [
            .zhHans: "密码错误，请重试",
            .en: "Wrong password, try again",
        ],
        "common_confirm": [
            .zhHans: "确定",
            .en: "OK",
        ],
        "common_delete": [
            .zhHans: "删除",
            .en: "Delete",
        ],
        "common_cancel": [
            .zhHans: "取消",
            .en: "Cancel",
        ],
        "common_close": [
            .zhHans: "关闭",
            .en: "Close",
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
