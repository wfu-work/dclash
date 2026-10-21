package com.cloudrift.dclash

import android.app.Application
import android.content.Context
import com.cloudrift.dclash.common.GlobalState

class DClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
