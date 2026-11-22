import Foundation


public enum Defaults {
    public static let work: Int64 = 1
    public static let study: Int64 = 2
    public static let fun: Int64 = 3
    public static let social: Int64 = 4
    public static let other: Int64 = 5

    public static let categories: [Category] = [
        Category(id: 1, name: "Work", color: "#4F7CFF"),
        Category(id: 2, name: "Learning", color: "#2FB985"),
        Category(id: 3, name: "Entertainment", color: "#FF6B6B"),
        Category(id: 4, name: "Social", color: "#FFB020"),
        Category(id: 5, name: "Other", color: "#9AA3B2"),
    ]

    public static let appCategories: [String: Int64] = [
        
        "com.apple.dt.Xcode": 1, "com.microsoft.VSCode": 1, "com.todesktop.230313mzl4w4u92": 1,
        "com.apple.Terminal": 1, "com.googlecode.iterm2": 1, "dev.warp.Warp-Stable": 1,
        "com.jetbrains.intellij": 1, "com.jetbrains.pycharm": 1, "com.jetbrains.WebStorm": 1,
        "com.apple.iWork.Pages": 1, "com.apple.iWork.Numbers": 1, "com.apple.iWork.Keynote": 1,
        "com.microsoft.Word": 1, "com.microsoft.Excel": 1, "com.microsoft.Powerpoint": 1,
        "notion.id": 1, "com.figma.Desktop": 1, "com.apple.finder": 1, "com.apple.mail": 1,
        "com.apple.Notes": 1, "md.obsidian": 1, "com.sublimetext.4": 1, "com.postmanlabs.mac": 1,
        "com.tencent.meeting": 1, "us.zoom.xos": 1, "com.larksuite.suite": 1, "com.electron.lark": 1,
        "com.alibaba.DingTalkMac": 1, "com.tinyspeck.slackmacgap": 1, "com.apple.Preview": 1,
        
        "com.apple.iBooksX": 2, "net.ankiweb.dtop": 2, "com.eusoft.eudic": 2,
        "com.eusoft.freeeudic": 2, "com.culturedcode.ThingsMac": 2, "com.readdle.PDFExpert-Mac": 2,
        
        "com.apple.Music": 3, "com.apple.TV": 3, "com.spotify.client": 3, "com.netease.163music": 3,
        "com.colliderli.iina": 3, "org.videolan.vlc": 3, "com.valvesoftware.steam": 3,
        "tv.danmaku.bili": 3, "com.apple.QuickTimePlayerX": 3, "com.tencent.QQMusicMac": 3,
        "com.apple.Photos": 3, "com.apple.podcasts": 3,
        
        "com.tencent.xinWeChat": 4, "com.tencent.qq": 4, "ru.keepcoder.Telegram": 4,
        "com.apple.MobileSMS": 4, "com.hnc.Discord": 4, "com.apple.FaceTime": 4,
        "net.whatsapp.WhatsApp": 4, "com.tencent.WeWorkMac": 4,
    ]

    
    public static let domainCategories: [String: Int64] = [
        "github.com": 1, "gitlab.com": 1, "stackoverflow.com": 1, "developer.apple.com": 1,
        "notion.so": 1, "figma.com": 1, "docs.google.com": 1, "feishu.cn": 1, "larksuite.com": 1,
        "codepen.io": 1, "vercel.com": 1, "cloudflare.com": 1, "aliyun.com": 1, "juejin.cn": 1,
        "csdn.net": 1, "mail.google.com": 1, "outlook.com": 1, "chatgpt.com": 1, "openai.com": 1,
        "claude.ai": 1, "gemini.google.com": 1, "deepseek.com": 1,
        "wikipedia.org": 2, "zhihu.com": 2, "coursera.org": 2, "edx.org": 2, "arxiv.org": 2,
        "scholar.google.com": 2, "cnki.net": 2, "mooc.cn": 2, "icourse163.org": 2, "khanacademy.org": 2,
        "bilibili.com": 3, "youtube.com": 3, "douyin.com": 3, "netflix.com": 3, "iqiyi.com": 3,
        "youku.com": 3, "v.qq.com": 3, "twitch.tv": 3, "steampowered.com": 3, "douban.com": 3,
        "xiaohongshu.com": 3, "tiktok.com": 3, "reddit.com": 3, "9gag.com": 3,
        "weibo.com": 4, "twitter.com": 4, "x.com": 4, "facebook.com": 4, "instagram.com": 4,
        "web.telegram.org": 4, "discord.com": 4, "wx.qq.com": 4, "tieba.baidu.com": 4,
    ]
}
