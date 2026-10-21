package com.cloudrift.dclash.service.models

data class NotificationParams(
    val title: String = "DClash",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)
