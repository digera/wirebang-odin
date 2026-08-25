package sounds

import wb "../wirebang"

play_thump :: proc(engine: ^wb.Engine = nil) {
	wb.play(engine, proc(ctx: ^wb.Ctx) {
		body := wb.osc(ctx, .Sine)
		wb.set_freq(body, wb.jitter(90, 0.05), 0)
		wb.ramp_freq(body, wb.safe_exp(wb.jitter(38, 0.05)), 0.12, .Exp)
		wb.start(body, 0)
		wb.stop(body, 0.12)

		click := wb.osc(ctx, .Triangle)
		wb.set_freq(click, wb.jitter(420, 0.1), 0)
		wb.ramp_freq(click, wb.safe_exp(wb.jitter(120, 0.1)), 0.018, .Exp)
		wb.start(click, 0)
		wb.stop(click, 0.018)

		amp := wb.gain(ctx)
		wb.set_gain(amp, wb.safe_exp(wb.jitter(0.28, 0.04)), 0)
		wb.ramp_gain(amp, 0.001, 0.12, .Exp)

		clickAmp := wb.gain(ctx)
		wb.set_gain(clickAmp, wb.safe_exp(wb.jitter(0.08, 0.1)), 0)
		wb.ramp_gain(clickAmp, 0.001, 0.018, .Exp)

		wb.connect(body, amp)
		wb.connect(amp, ctx.out)
		wb.connect(click, clickAmp)
		wb.connect(clickAmp, ctx.out)
	})
}
