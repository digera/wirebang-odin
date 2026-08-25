package sounds

import wb "../wirebang"

play_whoosh :: proc(engine: ^wb.Engine = nil) {
	wb.play(engine, proc(ctx: ^wb.Ctx) {
		air := wb.noise(ctx, 0.28)
		wb.start(air, 0)
		wb.stop(air, 0.28)

		sweep := wb.filter(ctx, .Bandpass, 2.2)
		wb.set_freq(sweep, wb.jitter(400, 0.05), 0)
		wb.ramp_freq(sweep, wb.safe_exp(wb.jitter(2800, 0.05)), 0.22, .Exp)

		body := wb.gain(ctx)
		wb.set_gain(body, wb.safe_exp(wb.jitter(0.18, 0.06)), 0)
		wb.ramp_gain(body, 0.001, 0.28, .Exp)

		move := wb.panner(ctx, -0.35)

		wb.connect(air, sweep)
		wb.connect(sweep, body)
		wb.connect(body, move)
		wb.connect(move, ctx.out)
	})
}
