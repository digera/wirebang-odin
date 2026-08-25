package sounds

import wb "../wirebang"

play_zap :: proc(engine: ^wb.Engine = nil) {
	wb.play(engine, proc(ctx: ^wb.Ctx) {
		snap := wb.noise(ctx, 0.025)
		wb.start(snap, 0)
		wb.stop(snap, 0.025)

		crackle := wb.noise(ctx, 0.012)
		wb.start(crackle, 0.003)
		wb.stop(crackle, 0.015)

		thump := wb.osc(ctx, .Sine)
		wb.set_freq(thump, wb.jitter(150, 0.08), 0)
		wb.ramp_freq(thump, wb.safe_exp(wb.jitter(55, 0.08)), 0.035, .Exp)
		wb.start(thump, 0)
		wb.stop(thump, 0.035)

		snapBp := wb.filter(ctx, .Bandpass, 1.5)
		wb.set_freq(snapBp, wb.jitter(2400, 0.12), 0)
		wb.ramp_freq(snapBp, wb.safe_exp(wb.jitter(650, 0.12)), 0.02, .Exp)

		crunch := wb.shaper(ctx, 6)

		snapGain := wb.gain(ctx)
		wb.set_gain(snapGain, wb.safe_exp(wb.jitter(0.26, 0.1)), 0)
		wb.ramp_gain(snapGain, 0.001, 0.025, .Exp)

		air := wb.filter(ctx, .Highpass, 0.7)
		wb.set_freq(air, 3800, 0)

		crackleGain := wb.gain(ctx)
		wb.set_gain(crackleGain, wb.safe_exp(wb.jitter(0.1, 0.1)), 0.003)
		wb.ramp_gain(crackleGain, 0.001, 0.015, .Exp)

		thumpGain := wb.gain(ctx)
		wb.set_gain(thumpGain, wb.safe_exp(wb.jitter(0.14, 0.08)), 0)
		wb.ramp_gain(thumpGain, 0.001, 0.035, .Exp)

		wb.connect(snap, snapBp)
		wb.connect(snapBp, crunch)
		wb.connect(crunch, snapGain)
		wb.connect(snapGain, ctx.out)
		wb.connect(crackle, air)
		wb.connect(air, crackleGain)
		wb.connect(crackleGain, ctx.out)
		wb.connect(thump, thumpGain)
		wb.connect(thumpGain, ctx.out)
	})
}
