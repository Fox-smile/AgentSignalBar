package com.agentsignal.bar.overlay

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.agentsignal.bar.model.DisplayState

/**
 * 桌面悬浮窗 — 可拖动的彩色信号灯圆点。
 *
 * 交互：
 * - 拖动：移动位置
 * - 单击：展开/收起详情面板
 * - 长按：无操作（预留）
 */
class SignalOverlayView(private val context: Context) {

    private var windowManager: WindowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private val dotSize = 48 // dp 转换为 px 的大小
    private val density = context.resources.displayMetrics.density
    private val dotSizePx = (dotSize * density).toInt()

    private var dotView: View? = null
    private var detailPanel: LinearLayout? = null
    private var isDetailShown = false
    private var isAttached = false

    private var currentState: DisplayState = DisplayState.DISCONNECTED
    private var currentLabel: String = ""

    // 动画
    private var pulseAnimator: ValueAnimator? = null
    private var pulseScale = 1.0f

    private val dotLayoutParams: WindowManager.LayoutParams by lazy {
        WindowManager.LayoutParams(
            dotSizePx,
            dotSizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (16 * density).toInt()
            y = (100 * density).toInt()
        }
    }

    private val detailLayoutParams: WindowManager.LayoutParams by lazy {
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (16 * density).toInt()
            y = (100 * density).toInt() + dotSizePx + (8 * density).toInt()
        }
    }

    /**
     * 创建圆点 View。
     */
    private fun createDotView(): View {
        return object : View(context) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            private var initX = 0f
            private var initY = 0f
            private var isDragging = false
            private val dragThreshold = 10f

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)

                // 颜色
                paint.color = when (currentState) {
                    DisplayState.READY -> Color.parseColor("#4CAF50")
                    DisplayState.ACTIVE -> Color.parseColor("#FF9800")
                    DisplayState.BLOCKED -> Color.parseColor("#F44336")
                    DisplayState.PAUSED -> Color.parseColor("#9E9E9E")
                    DisplayState.DISCONNECTED -> Color.parseColor("#9E9E9E")
                }

                // 呼吸动画：忙碌时脉冲，卡住时快速闪烁
                val radius = (width / 2f) * pulseScale
                canvas.drawCircle(width / 2f, height / 2f, radius, paint)

                // 外圈光晕
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 2f
                paint.alpha = 80
                canvas.drawCircle(width / 2f, height / 2f, radius + 4f, paint)
                paint.style = Paint.Style.FILL
                paint.alpha = 255
            }

            override fun onTouchEvent(event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initX = event.rawX
                        initY = event.rawY
                        isDragging = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initX
                        val dy = event.rawY - initY
                        if (kotlin.math.abs(dx) > dragThreshold ||
                            kotlin.math.abs(dy) > dragThreshold
                        ) {
                            isDragging = true
                            dotLayoutParams.x = (dotLayoutParams.x - dx).toInt()
                            dotLayoutParams.y = (dotLayoutParams.y + dy).toInt()
                            windowManager.updateViewLayout(this, dotLayoutParams)
                            initX = event.rawX
                            initY = event.rawY
                            // 同步移动详情面板
                            detailPanel?.let {
                                detailLayoutParams.x = dotLayoutParams.x
                                detailLayoutParams.y =
                                    dotLayoutParams.y + dotSizePx + (8 * density).toInt()
                                windowManager.updateViewLayout(it, detailLayoutParams)
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            toggleDetail()
                        }
                        return true
                    }
                }
                return super.onTouchEvent(event)
            }
        }.apply {
            layoutParams = FrameLayout.LayoutParams(dotSizePx, dotSizePx)
        }
    }

    /**
     * 创建详情面板。
     */
    private fun createDetailPanel(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                (12 * density).toInt(),
                (8 * density).toInt(),
                (12 * density).toInt(),
                (8 * density).toInt()
            )
            setBackgroundColor(Color.argb(220, 30, 30, 40))

            // 圆角
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(
                        0, 0, view.width, view.height,
                        12f * density
                    )
                }
            }
            clipToOutline = true

            // 状态文本
            addView(TextView(context).apply {
                text = currentLabel
                setTextColor(Color.WHITE)
                textSize = 14f
                setPadding(0, 0, 0, (4 * density).toInt())
            })
        }
    }

    private fun toggleDetail() {
        if (isDetailShown) {
            detailPanel?.let { windowManager.removeView(it) }
            detailPanel = null
        } else {
            detailPanel = createDetailPanel()
            detailLayoutParams.x = dotLayoutParams.x
            detailLayoutParams.y = dotLayoutParams.y + dotSizePx + (8 * density).toInt()
            detailPanel?.let { windowManager.addView(it, detailLayoutParams) }
        }
        isDetailShown = !isDetailShown
    }

    /**
     * 更新状态和动画。
     */
    fun updateState(state: DisplayState, label: String) {
        currentState = state
        currentLabel = label

        // 更新详情面板文本
        detailPanel?.let { panel ->
            if (panel.childCount > 0) {
                (panel.getChildAt(0) as? TextView)?.text = label
            }
        }

        // 动画控制
        when (state) {
            DisplayState.ACTIVE -> startPulseAnimation(1.0f, 0.7f, 800L)
            DisplayState.BLOCKED -> startPulseAnimation(1.0f, 0.5f, 400L)
            else -> stopPulseAnimation()
        }

        dotView?.invalidate()
    }

    private fun startPulseAnimation(from: Float, to: Float, duration: Long) {
        pulseAnimator?.cancel()
        pulseAnimator = ValueAnimator.ofFloat(from, to).apply {
            this.duration = duration
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { animation ->
                pulseScale = animation.animatedValue as Float
                dotView?.invalidate()
            }
            start()
        }
    }

    private fun stopPulseAnimation() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        pulseScale = 1.0f
        dotView?.invalidate()
    }

    /**
     * 显示悬浮窗。
     */
    fun show() {
        if (isAttached) return
        dotView = createDotView()
        dotView?.let { windowManager.addView(it, dotLayoutParams) }
        isAttached = true
    }

    /**
     * 隐藏悬浮窗。
     */
    fun hide() {
        if (!isAttached) return
        stopPulseAnimation()
        dotView?.let { windowManager.removeView(it) }
        detailPanel?.let { windowManager.removeView(it) }
        dotView = null
        detailPanel = null
        isDetailShown = false
        isAttached = false
    }
}
