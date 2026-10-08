/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package com.gitsnup.robustbricks;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;

import java.util.Locale;
import java.util.Random;

/** Canvas implementation of the complete Robust Bricks game for Android. */
public final class GameView extends View {
    private static final int BRICK_ROWS = 6, BRICK_COLUMNS = 8;
    private static final int HANDCRAFTED_LEVEL_COUNT = 5;
    private static final int MAX_BALLS_LEFT = 9, MAX_BALLS_IN_PLAY = 8;
    private static final int MAX_CAPSULES = 6, MAX_PIECES = 192, TRAIL_LENGTH = 6;
    private static final float LOGICAL_WIDTH = 320f;
    private static final float BRICK_WIDTH = 36f, BRICK_HEIGHT = 14f, BRICK_GAP = 4f;
    private static final float BRICKS_TOP = 94f, PADDLE_HEIGHT = 10f;
    private static final float PADDLE_FROM_BOTTOM = 50f, BALL_SIZE = 8f, BALL_SPEED = 4f;
    private static final float CAPSULE_WIDTH = 26f, CAPSULE_HEIGHT = 14f, CAPSULE_SPEED = 2f;
    private static final int POWER_UP_TICKS = 15 * 60, FLASH_TICKS = 24;
    private static final int PIECE_COLUMNS = 4, PIECE_ROWS = 2, PIECE_TICKS = 30;
    private static final float PIECE_GRAVITY = 0.25f;

    private static final int TITLE = 0, HOW_TO_PLAY = 1, SERVING = 2, PLAYING = 3,
            PAUSED = 4, LEVEL_COMPLETE = 5, LOST = 6;
    private static final int BALL = 0, PADDLE = 1, SLOW = 2, MULTI = 3, SHRINK = 4;
    private static final int BOUNCE = 0, WALL = 1, EXPLODE = 2, POWER_UP = 3, POWER_DOWN = 4;
    private static final String[] DIFFICULTY_NAMES = {"Casual", "Classic", "Tough", "Expert"};
    private static final float[] SPEED_MULTIPLIERS = {0.8f, 1.0f, 1.4f, 1.8f};
    private static final float[] PADDLE_WIDTHS = {80f, 64f, 56f, 48f};
    private static final int[] STARTING_BALLS = {5, 3, 2, 1};
    private static final int[] BRICK_DENSITY = {614, 717, 768, 819};
    private static final int[] CAPSULE_CHANCES = {230, 171, 128, 85};
    private static final int[] SCORE_MULTIPLIERS = {1, 1, 2, 3};
    private static final int[] BRICK_SCORES = {60, 50, 40, 30, 20, 10};
    private static final int[] BRICK_COLORS = {
            Color.rgb(230, 51, 51), Color.rgb(242, 140, 38), Color.rgb(242, 217, 51),
            Color.rgb(77, 204, 77), Color.rgb(51, 179, 230), Color.rgb(115, 89, 230)};
    private static final int[] POWER_COLORS = {
            Color.rgb(204, 77, 191), Color.rgb(64, 128, 242), Color.rgb(51, 179, 89),
            Color.rgb(242, 140, 26), Color.rgb(230, 26, 26)};
    private static final String[] POWER_LETTERS = {"B", "P", "S", "M", "R"};
    private static final String[] POWER_DESCRIPTIONS = {
            "Ball added", "Paddle wider (15 seconds)", "Slower ball (15 seconds)",
            "Two extra balls", "Paddle smaller (15 seconds)"};
    private static final int[][] LEVEL_LAYOUTS = {
            {0x3c, 0x7e, 0xff, 0xff, 0x7e, 0x3c},
            {0xff, 0x00, 0xff, 0x00, 0xff, 0x00},
            {0x81, 0xc3, 0x66, 0x3c, 0x66, 0xc3},
            {0xff, 0x99, 0x99, 0xff, 0x99, 0x99}
    };

    private static final class BallState {
        boolean active;
        float x, y, dx, dy;
        final float[] trailX = new float[TRAIL_LENGTH];
        final float[] trailY = new float[TRAIL_LENGTH];
        int trailCount;
        BallState copy() {
            BallState b = new BallState();
            b.active = active; b.x = x; b.y = y; b.dx = dx; b.dy = dy;
            b.trailCount = trailCount;
            System.arraycopy(trailX, 0, b.trailX, 0, TRAIL_LENGTH);
            System.arraycopy(trailY, 0, b.trailY, 0, TRAIL_LENGTH);
            return b;
        }
    }
    private static final class CapsuleState {
        boolean active; float x, y; int type;
    }
    private static final class PieceState {
        boolean active; float x, y, dx, dy, gravity; int ticksLeft, lifeTicks, row;
    }

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Random random = new Random();
    private final SharedPreferences prefs;
    private final SoundPool soundPool;
    private final int[] soundIds = new int[5];
    private boolean soundEnabled;
    private boolean loopRunning;
    private float scale = 1f, logicalHeight = 568f, paddleX = LOGICAL_WIDTH / 2f;
    private final boolean[][] bricks = new boolean[BRICK_ROWS][BRICK_COLUMNS];
    private int bricksLeft, level = 1, score, ballsLeft, timerTicks;
    private boolean timerRunning, newRecord;
    private int difficulty = 1, state = TITLE, pausedState = SERVING;
    private final int[] bestLevel = new int[4], gamesPlayed = new int[4];
    private final BallState[] balls = new BallState[MAX_BALLS_IN_PLAY];
    private final CapsuleState[] capsules = new CapsuleState[MAX_CAPSULES];
    private final PieceState[] pieces = new PieceState[MAX_PIECES];
    private int longPaddleTicks, shortPaddleTicks, slowTicks, flashTicks, flashType;

    private final Runnable frame = new Runnable() {
        @Override public void run() {
            if (!loopRunning) return;
            tick();
            postInvalidateOnAnimation();
            handler.postDelayed(this, 16L);
        }
    };

    public GameView(Context context) {
        super(context);
        setLayerType(View.LAYER_TYPE_SOFTWARE, null);
        setFocusable(true);
        setFocusableInTouchMode(true);
        prefs = context.getSharedPreferences("robust_bricks", Context.MODE_PRIVATE);
        for (int i = 0; i < 4; i++) {
            bestLevel[i] = prefs.getInt(bestKey(i), 0);
            gamesPlayed[i] = prefs.getInt(gamesKey(i), 0);
        }
        difficulty = clamp(prefs.getInt("difficulty", 1), 0, 3);
        soundEnabled = prefs.getBoolean("sound_enabled", true);
        for (int i = 0; i < MAX_BALLS_IN_PLAY; i++) balls[i] = new BallState();
        for (int i = 0; i < MAX_CAPSULES; i++) capsules[i] = new CapsuleState();
        for (int i = 0; i < MAX_PIECES; i++) pieces[i] = new PieceState();
        AudioAttributes audio = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
        soundPool = new SoundPool.Builder().setMaxStreams(8).setAudioAttributes(audio).build();
        soundIds[BOUNCE] = soundPool.load(context, R.raw.bounce, 1);
        soundIds[WALL] = soundPool.load(context, R.raw.wall, 1);
        soundIds[EXPLODE] = soundPool.load(context, R.raw.explode, 1);
        soundIds[POWER_UP] = soundPool.load(context, R.raw.powerup, 1);
        soundIds[POWER_DOWN] = soundPool.load(context, R.raw.powerdown, 1);
        resetGame();
        state = TITLE;
        paint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        paint.setTextAlign(Paint.Align.CENTER);
    }

    private static int clamp(int value, int min, int max) { return Math.max(min, Math.min(max, value)); }
    private String bestKey(int d) { return "best_level_" + d; }
    private String gamesKey(int d) { return "games_played_" + d; }
    private float height() { return logicalHeight; }
    private float paddleY() { return height() - PADDLE_FROM_BOTTOM; }
    private float bricksLeftEdge() { return (LOGICAL_WIDTH - (BRICK_COLUMNS * BRICK_WIDTH + (BRICK_COLUMNS - 1) * BRICK_GAP)) / 2f; }
    private float paddleWidth() {
        float base = PADDLE_WIDTHS[difficulty];
        if (longPaddleTicks > 0) return base + 24f;
        if (shortPaddleTicks > 0) return Math.max(36f, base * 0.75f);
        return base;
    }

    @Override protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        scale = w > 0 ? w / LOGICAL_WIDTH : 1f;
        logicalHeight = h / scale;
        if (oldw == 0) paddleX = LOGICAL_WIDTH / 2f;
        else movePaddleTo(paddleX);
    }

    public void resumeLoop() {
        if (!loopRunning) { loopRunning = true; handler.removeCallbacks(frame); handler.post(frame); }
    }
    public void pauseLoop() { loopRunning = false; handler.removeCallbacks(frame); }
    public void releaseAudio() { pauseLoop(); soundPool.release(); }

    private void tick() {
        if (timerRunning) timerTicks++;
        if (state == SERVING) placeBallOnPaddle();
        else if (state == PLAYING) play();
        if (state != PAUSED) movePieces();
    }

    private void loadLevel(int newLevel) {
        level = newLevel;
        if (level == 1 || level > HANDCRAFTED_LEVEL_COUNT) { randomizeBricks(); return; }
        bricksLeft = 0;
        int[] layout = LEVEL_LAYOUTS[level - 2];
        for (int row = 0; row < BRICK_ROWS; row++) for (int col = 0; col < BRICK_COLUMNS; col++) {
            bricks[row][col] = (layout[row] & (1 << col)) != 0;
            if (bricks[row][col]) bricksLeft++;
        }
    }

    private void randomizeBricks() {
        do {
            bricksLeft = 0;
            for (int row = 0; row < BRICK_ROWS; row++) for (int col = 0; col < BRICK_COLUMNS / 2; col++) {
                boolean present = random.nextInt(1024) < BRICK_DENSITY[difficulty];
                bricks[row][col] = present;
                bricks[row][BRICK_COLUMNS - 1 - col] = present;
                if (present) bricksLeft += 2;
            }
        } while (bricksLeft < 16);
    }

    private void resetGame() {
        loadLevel(1);
        clearPowerUps();
        for (PieceState piece : pieces) piece.active = false;
        ballsLeft = STARTING_BALLS[difficulty];
        score = 0; timerTicks = 0; timerRunning = false; newRecord = false;
        paddleX = LOGICAL_WIDTH / 2f; state = SERVING;
        placeBallOnPaddle();
    }

    private void recordLevelReached() {
        if (level > bestLevel[difficulty]) {
            bestLevel[difficulty] = level;
            newRecord = true;
            prefs.edit().putInt(bestKey(difficulty), level).apply();
        }
    }

    private void startLevel(int newLevel) {
        loadLevel(newLevel);
        recordLevelReached();
        clearPowerUps();
        movePaddleTo(paddleX);
        timerRunning = false; state = SERVING;
        placeBallOnPaddle();
    }

    private void placeBallOnPaddle() {
        BallState b = balls[0];
        b.active = true; b.x = paddleX - BALL_SIZE / 2f; b.y = paddleY() - BALL_SIZE;
        b.dx = 0; b.dy = 0; b.trailCount = 0;
    }

    private void movePaddleTo(float x) {
        float half = paddleWidth() / 2f;
        paddleX = Math.max(half, Math.min(LOGICAL_WIDTH - half, x));
    }

    private void clearPowerUps() {
        longPaddleTicks = shortPaddleTicks = slowTicks = flashTicks = 0;
        for (CapsuleState c : capsules) c.active = false;
        for (BallState b : balls) b.active = false;
    }

    private void play() {
        if (flashTicks > 0) flashTicks--;
        if (longPaddleTicks > 0 && --longPaddleTicks == 0) movePaddleTo(paddleX);
        if (shortPaddleTicks > 0 && --shortPaddleTicks == 0) movePaddleTo(paddleX);
        if (slowTicks > 0) slowTicks--;
        int speedIncrease = Math.min(10, (level - 1) / 5);
        float factor = SPEED_MULTIPLIERS[difficulty] * (1f + speedIncrease * 0.05f) * (slowTicks > 0 ? 0.5f : 1f);
        int steps = factor > 2f ? 3 : (factor > 1f ? 2 : 1);
        float stepFactor = factor / steps;
        boolean anyBall = false;
        for (BallState b : balls) {
            if (state != PLAYING) break;
            if (b.active) recordTrail(b);
            for (int step = 0; step < steps && b.active && state == PLAYING; step++) moveBall(b, stepFactor);
            anyBall |= b.active;
        }
        if (state != PLAYING) return;
        moveCapsules();
        if (!anyBall) {
            ballsLeft--;
            clearPowerUps();
            movePaddleTo(paddleX);
            state = ballsLeft > 0 ? SERVING : LOST;
            timerRunning = state != LOST;
        }
    }

    private void recordTrail(BallState b) {
        for (int i = TRAIL_LENGTH - 1; i > 0; i--) { b.trailX[i] = b.trailX[i - 1]; b.trailY[i] = b.trailY[i - 1]; }
        b.trailX[0] = b.x; b.trailY[0] = b.y;
        if (b.trailCount < TRAIL_LENGTH) b.trailCount++;
    }

    private static boolean overlaps(float ax, float ay, float aw, float ah, float bx, float by, float bw, float bh) {
        return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
    }

    private void moveBall(BallState b, float factor) {
        b.x += b.dx * factor; b.y += b.dy * factor;
        boolean hitWall = false;
        if (b.x < 0) { b.x = 0; b.dx = Math.abs(b.dx); hitWall = true; }
        else if (b.x + BALL_SIZE > LOGICAL_WIDTH) { b.x = LOGICAL_WIDTH - BALL_SIZE; b.dx = -Math.abs(b.dx); hitWall = true; }
        if (b.y < 0) { b.y = 0; b.dy = Math.abs(b.dy); hitWall = true; }
        if (hitWall) playSound(WALL);
        if (b.y > height()) { b.active = false; return; }

        float width = paddleWidth(), left = paddleX - width / 2f;
        if (b.dy > 0 && overlaps(b.x, b.y, BALL_SIZE, BALL_SIZE, left, paddleY(), width, PADDLE_HEIGHT)) {
            b.y = paddleY() - BALL_SIZE; b.dy = -Math.abs(b.dy); playSound(BOUNCE);
            float offset = (b.x + BALL_SIZE / 2f - paddleX) / (width / 2f);
            b.dx = offset * BALL_SPEED;
            if (Math.abs(b.dx) < 0.75f) b.dx = b.dx < 0 ? -0.75f : 0.75f;
            return;
        }

        for (int row = 0; row < BRICK_ROWS; row++) for (int col = 0; col < BRICK_COLUMNS; col++) {
            if (!bricks[row][col]) continue;
            float x = bricksLeftEdge() + col * (BRICK_WIDTH + BRICK_GAP);
            float y = BRICKS_TOP + row * (BRICK_HEIGHT + BRICK_GAP);
            if (!overlaps(b.x, b.y, BALL_SIZE, BALL_SIZE, x, y, BRICK_WIDTH, BRICK_HEIGHT)) continue;
            bricks[row][col] = false; bricksLeft--;
            score = score > Integer.MAX_VALUE - BRICK_SCORES[row] * SCORE_MULTIPLIERS[difficulty]
                    ? Integer.MAX_VALUE : score + BRICK_SCORES[row] * SCORE_MULTIPLIERS[difficulty];
            playSound(EXPLODE); shatterBrick(x, y, row, b);
            float overlapX = b.dx > 0 ? b.x + BALL_SIZE - x : x + BRICK_WIDTH - b.x;
            float overlapY = b.dy > 0 ? b.y + BALL_SIZE - y : y + BRICK_HEIGHT - b.y;
            if (overlapX < overlapY) b.dx = -b.dx; else b.dy = -b.dy;
            if (bricksLeft == 0) {
                clearPowerUps(); timerRunning = false; state = LEVEL_COMPLETE;
            } else dropCapsule(x + BRICK_WIDTH / 2f, y);
            return;
        }
    }

    private void shatterBrick(float x, float y, int row, BallState ball) {
        float pieceWidth = BRICK_WIDTH / PIECE_COLUMNS, pieceHeight = BRICK_HEIGHT / PIECE_ROWS;
        int slot = 0;
        for (int pr = 0; pr < PIECE_ROWS; pr++) for (int pc = 0; pc < PIECE_COLUMNS; pc++) {
            while (slot < MAX_PIECES && pieces[slot].active) slot++;
            if (slot == MAX_PIECES) return;
            PieceState p = pieces[slot++]; p.active = true;
            p.x = x + pc * pieceWidth; p.y = y + pr * pieceHeight;
            float fromCenter = p.x + pieceWidth / 2f - (x + BRICK_WIDTH / 2f);
            p.dx = fromCenter * 0.12f + ball.dx * 0.3f + jitter(0.4f);
            p.dy = -1.5f - (PIECE_ROWS - 1 - pr) * 0.5f + ball.dy * 0.2f + jitter(0.4f);
            p.gravity = PIECE_GRAVITY; p.ticksLeft = PIECE_TICKS; p.lifeTicks = PIECE_TICKS; p.row = row;
        }
    }

    private void movePieces() {
        for (PieceState p : pieces) if (p.active) {
            p.x += p.dx; p.y += p.dy; p.dy += p.gravity;
            if (--p.ticksLeft == 0) p.active = false;
        }
    }

    private void dropCapsule(float centerX, float y) {
        if (random.nextInt(1024) >= CAPSULE_CHANCES[difficulty]) return;
        for (CapsuleState c : capsules) if (!c.active) {
            c.active = true; c.x = centerX - CAPSULE_WIDTH / 2f; c.y = y; c.type = random.nextInt(5); return;
        }
    }

    private void moveCapsules() {
        float width = paddleWidth();
        for (CapsuleState c : capsules) if (c.active) {
            c.y += CAPSULE_SPEED;
            if (overlaps(c.x, c.y, CAPSULE_WIDTH, CAPSULE_HEIGHT, paddleX - width / 2f, paddleY(), width, PADDLE_HEIGHT)) {
                c.active = false; playSound(c.type == SHRINK ? POWER_DOWN : POWER_UP);
                applyPowerUp(c.type); flashTicks = FLASH_TICKS; flashType = c.type;
            } else if (c.y > height()) c.active = false;
        }
    }

    private void applyPowerUp(int type) {
        switch (type) {
            case BALL: if (ballsLeft < MAX_BALLS_LEFT) ballsLeft++; break;
            case PADDLE:
                if (shortPaddleTicks > 0) shortPaddleTicks = 0; else longPaddleTicks = POWER_UP_TICKS;
                movePaddleTo(paddleX); break;
            case SLOW: slowTicks = POWER_UP_TICKS; break;
            case MULTI: addBalls(2); break;
            case SHRINK:
                if (longPaddleTicks > 0) longPaddleTicks = 0; else shortPaddleTicks = POWER_UP_TICKS;
                movePaddleTo(paddleX); break;
            default: break;
        }
    }

    private void addBalls(int count) {
        BallState source = null;
        for (BallState b : balls) if (b.active) { source = b; break; }
        if (source == null) return;
        BallState copy = source.copy();
        float[] directions = {-BALL_SPEED * 0.8f, BALL_SPEED * 0.8f};
        for (int i = 0; i < balls.length && count > 0; i++) if (!balls[i].active) {
            BallState b = balls[i];
            System.arraycopy(copy.trailX, 0, b.trailX, 0, TRAIL_LENGTH);
            System.arraycopy(copy.trailY, 0, b.trailY, 0, TRAIL_LENGTH);
            b.active = true; b.x = copy.x; b.y = copy.y; b.trailCount = copy.trailCount;
            b.dx = directions[count & 1]; b.dy = -BALL_SPEED; count--;
        }
    }

    private float jitter(float amount) { return (random.nextFloat() - 0.5f) * 2f * amount; }
    private void playSound(int sound) { if (soundEnabled && soundIds[sound] != 0) soundPool.play(soundIds[sound], 1f, 1f, 1, 0, 1f); }

    private RectF howButton() { return new RectF(60, height() * .66f, 260, height() * .66f + 36); }
    private RectF difficultyButton() { return new RectF(60, height() * .75f, 260, height() * .75f + 36); }
    private RectF soundButton() { return new RectF(60, height() * .84f, 260, height() * .84f + 36); }
    private RectF backButton() { return new RectF(60, height() * .86f, 260, height() * .86f + 36); }
    private RectF pauseButton() { return new RectF(LOGICAL_WIDTH - 70, 42, LOGICAL_WIDTH - 10, 72); }
    private RectF resumeButton() { return new RectF(60, height() * .47f, 260, height() * .47f + 36); }
    private RectF restartButton() { return new RectF(60, height() * .59f, 260, height() * .59f + 36); }
    private RectF returnButton() { return new RectF(60, height() * .71f, 260, height() * .71f + 36); }

    @Override public boolean onTouchEvent(MotionEvent event) {
        float x = event.getX() / scale, y = event.getY() / scale;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                handleTouchDown(x, y); invalidate(); return true;
            case MotionEvent.ACTION_MOVE:
                if (state == SERVING || state == PLAYING) { movePaddleTo(x); invalidate(); }
                return true;
            case MotionEvent.ACTION_UP: performClick(); return true;
            default: return true;
        }
    }

    @Override public boolean performClick() { super.performClick(); return true; }

    private boolean contains(RectF r, float x, float y) { return r.contains(x, y); }
    private void handleTouchDown(float x, float y) {
        if (state == PAUSED) {
            if (contains(resumeButton(), x, y)) { state = pausedState; timerRunning = state == PLAYING; playSound(BOUNCE); }
            else if (contains(restartButton(), x, y)) {
                gamesPlayed[difficulty]++; prefs.edit().putInt(gamesKey(difficulty), gamesPlayed[difficulty]).apply();
                resetGame(); recordLevelReached(); playSound(BOUNCE);
            } else if (contains(returnButton(), x, y)) { timerRunning = false; state = TITLE; playSound(BOUNCE); }
            return;
        }
        if ((state == SERVING || state == PLAYING || state == LEVEL_COMPLETE) && contains(pauseButton(), x, y)) {
            pausedState = state; timerRunning = false; state = PAUSED; playSound(BOUNCE); return;
        }
        if (state == SERVING || state == PLAYING || state == LEVEL_COMPLETE) movePaddleTo(x);
        if (state == SERVING) {
            balls[0].dx = BALL_SPEED * 0.6f; balls[0].dy = -BALL_SPEED;
            state = PLAYING; timerRunning = true;
        } else if (state == LEVEL_COMPLETE) { startLevel(level + 1); playSound(BOUNCE); }
        else if (state == TITLE && contains(howButton(), x, y)) { state = HOW_TO_PLAY; playSound(BOUNCE); }
        else if (state == HOW_TO_PLAY) { if (contains(backButton(), x, y)) { state = TITLE; playSound(BOUNCE); } }
        else if (state == TITLE && contains(difficultyButton(), x, y)) {
            difficulty = (difficulty + 1) % DIFFICULTY_NAMES.length;
            prefs.edit().putInt("difficulty", difficulty).apply(); playSound(BOUNCE);
        } else if (state == TITLE && contains(soundButton(), x, y)) {
            soundEnabled = !soundEnabled; prefs.edit().putBoolean("sound_enabled", soundEnabled).apply(); playSound(BOUNCE);
        } else if (state == TITLE) {
            gamesPlayed[difficulty]++; prefs.edit().putInt(gamesKey(difficulty), gamesPlayed[difficulty]).apply();
            resetGame(); recordLevelReached();
        } else if (state == LOST) state = TITLE;
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (getWidth() <= 0) return;
        scale = getWidth() / LOGICAL_WIDTH;
        logicalHeight = getHeight() / scale;
        canvas.save(); canvas.scale(scale, scale);
        canvas.drawColor(Color.BLACK);
        paint.setColor(Color.WHITE); paint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        paint.setTextAlign(Paint.Align.CENTER); paint.setAlpha(255);
        if (state == TITLE) drawTitle(canvas);
        else if (state == HOW_TO_PLAY) drawHowToPlay(canvas);
        else if (state == PAUSED) drawPaused(canvas);
        else drawGame(canvas);
        canvas.restore();
    }

    private void drawText(Canvas c, String text, float centerX, float top, float size) {
        paint.setTextSize(size); paint.setTextAlign(Paint.Align.CENTER);
        Paint.FontMetrics fm = paint.getFontMetrics();
        c.drawText(text, centerX, top + (size - (fm.bottom - fm.top)) / 2f - fm.top, paint);
    }
    private void drawLeftText(Canvas c, String text, float x, float top, float size) {
        paint.setTextSize(size); paint.setTextAlign(Paint.Align.LEFT);
        Paint.FontMetrics fm = paint.getFontMetrics();
        c.drawText(text, x, top + (size - (fm.bottom - fm.top)) / 2f - fm.top, paint);
        paint.setTextAlign(Paint.Align.CENTER);
    }
    private void drawButton(Canvas c, RectF rect, String text) {
        paint.setColor(Color.rgb(64, 64, 77));
        c.drawRect(rect, paint); paint.setColor(Color.WHITE);
        drawText(c, text, rect.centerX(), rect.top + 3f, 18f);
    }
    private String formatTime() {
        int seconds = timerTicks / 60;
        return String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60);
    }
    private String bestLevelLabel() {
        return bestLevel[difficulty] > 0 ? Integer.toString(bestLevel[difficulty]) : "none yet";
    }

    private void drawTitle(Canvas c) {
        drawText(c, "ROBUST", LOGICAL_WIDTH / 2f, height() * .14f, 44f);
        drawText(c, "BRICKS", LOGICAL_WIDTH / 2f, height() * .14f + 48f, 44f);
        float brickWidth = 36f, gap = 6f;
        float left = (LOGICAL_WIDTH - BRICK_ROWS * brickWidth - (BRICK_ROWS - 1) * gap) / 2f;
        for (int i = 0; i < BRICK_ROWS; i++) {
            paint.setColor(BRICK_COLORS[i]);
            c.drawRect(left + i * (brickWidth + gap), height() * .14f + 112f,
                    left + i * (brickWidth + gap) + brickWidth, height() * .14f + 126f, paint);
        }
        drawText(c, "Best level (" + DIFFICULTY_NAMES[difficulty] + "): " + bestLevelLabel(), LOGICAL_WIDTH / 2f, height() * .44f, 16f);
        drawText(c, "Games played (" + DIFFICULTY_NAMES[difficulty] + "): " + gamesPlayed[difficulty], LOGICAL_WIDTH / 2f, height() * .44f + 30f, 16f);
        drawText(c, "Tap to play", LOGICAL_WIDTH / 2f, height() * .56f, 22f);
        drawButton(c, howButton(), "How to Play");
        drawButton(c, difficultyButton(), "Difficulty: " + DIFFICULTY_NAMES[difficulty]);
        drawButton(c, soundButton(), "Sound: " + (soundEnabled ? "On" : "Off"));
    }

    private void drawHowToPlay(Canvas c) {
        drawText(c, "HOW TO PLAY", LOGICAL_WIDTH / 2f, 24, 28);
        String[] intro = {
                "Drag to move; tap to serve. Tap Pause for the menu.",
                "Five opening boards, then endless random boards.",
                "Ball speed rises every five levels. Difficulty changes speed,",
                "paddle width, lives, board density, drops and score multiplier.",
                "Brick rows score 60, 50, 40, 30, 20 and 10 points."
        };
        for (int i = 0; i < intro.length; i++) drawLeftText(c, intro[i], 16, 70 + i * 19, 13);
        drawLeftText(c, "Catch capsules with the paddle:", 16, 174, 14);
        for (int i = 0; i < POWER_DESCRIPTIONS.length; i++) {
            float y = 202 + i * 31;
            drawCapsule(c, i, 20, y);
            drawLeftText(c, POWER_DESCRIPTIONS[i], 60, y - 3, 14);
        }
        drawLeftText(c, "P and R cancel. Losing a life ends P, S and R.", 16, 366, 13);
        drawButton(c, backButton(), "Go Back");
    }

    private void drawPaused(Canvas c) {
        drawText(c, "PAUSED", LOGICAL_WIDTH / 2f, height() * .28f, 36);
        drawButton(c, resumeButton(), "Resume");
        drawButton(c, restartButton(), "Restart Run");
        drawButton(c, returnButton(), "Return to Title");
    }

    private void drawGame(Canvas c) {
        float left = bricksLeftEdge();
        for (int row = 0; row < BRICK_ROWS; row++) {
            paint.setColor(BRICK_COLORS[row]);
            for (int col = 0; col < BRICK_COLUMNS; col++) if (bricks[row][col]) {
                float x = left + col * (BRICK_WIDTH + BRICK_GAP), y = BRICKS_TOP + row * (BRICK_HEIGHT + BRICK_GAP);
                c.drawRect(x, y, x + BRICK_WIDTH, y + BRICK_HEIGHT, paint);
            }
        }
        float pw = BRICK_WIDTH / PIECE_COLUMNS, ph = BRICK_HEIGHT / PIECE_ROWS;
        for (PieceState p : pieces) if (p.active) {
            float life = p.ticksLeft / (float)p.lifeTicks, size = .5f + .5f * life;
            paint.setColor(BRICK_COLORS[p.row]); paint.setAlpha((int)(255 * life));
            c.drawRect(p.x + pw * (1-size)/2f, p.y + ph * (1-size)/2f,
                    p.x + pw * (1-size)/2f + pw * size, p.y + ph * (1-size)/2f + ph * size, paint);
        }
        paint.setAlpha(255); paint.setColor(Color.WHITE);
        drawLeftText(c, "Time: " + formatTime(), 10, 20, 16);
        paint.setTextAlign(Paint.Align.RIGHT);
        drawRightText(c, "Balls: " + ballsLeft, LOGICAL_WIDTH - 10, 20, 16);
        paint.setTextAlign(Paint.Align.CENTER);
        drawLeftText(c, "Level " + level, 10, 42, 16);
        drawText(c, "Score: " + score, LOGICAL_WIDTH / 2f, 42, 16);
        String effects = effectText();
        if (!effects.isEmpty()) drawText(c, effects, LOGICAL_WIDTH / 2f, 68, 16);
        if (state == SERVING || state == PLAYING || state == LEVEL_COMPLETE) drawButton(c, pauseButton(), "Pause");

        if (state == LEVEL_COMPLETE) {
            drawText(c, "LEVEL CLEARED", LOGICAL_WIDTH/2f, height()/2f - 50, 32);
            drawText(c, "Level " + level, LOGICAL_WIDTH/2f, height()/2f, 18);
            if (newRecord) drawText(c, "NEW BEST LEVEL!", LOGICAL_WIDTH/2f, height()/2f + 30, 20);
            drawText(c, "Tap for next level", LOGICAL_WIDTH/2f, height()/2f + 60, 18);
            return;
        }
        if (state == LOST) {
            drawText(c, "GAME OVER", LOGICAL_WIDTH/2f, height()/2f - 60, 40);
            drawText(c, "Score: " + score, LOGICAL_WIDTH/2f, height()/2f, 20);
            drawText(c, "Best level: " + bestLevel[difficulty], LOGICAL_WIDTH/2f, height()/2f + 32, 18);
            drawText(c, "Tap to return", LOGICAL_WIDTH/2f, height()/2f + 90, 18);
            return;
        }

        for (CapsuleState capsule : capsules) if (capsule.active) drawCapsule(c, capsule.type, capsule.x, capsule.y);
        for (BallState b : balls) if (b.active) {
            for (int j = b.trailCount - 1; j >= 0; j--) {
                float life = (TRAIL_LENGTH - j) / (float)(TRAIL_LENGTH + 1), size = BALL_SIZE * (.4f + .6f * life);
                paint.setColor(Color.WHITE); paint.setAlpha((int)(128 * life));
                c.drawRect(b.trailX[j] + (BALL_SIZE-size)/2f, b.trailY[j] + (BALL_SIZE-size)/2f,
                        b.trailX[j] + (BALL_SIZE-size)/2f + size, b.trailY[j] + (BALL_SIZE-size)/2f + size, paint);
            }
        }
        float flash = flashTicks / (float)FLASH_TICKS;
        int normal = Color.rgb(230, 230, 230), fc = flashTicks > 0 ? POWER_COLORS[flashType] : normal;
        paint.setColor(flashTicks > 0 ? blend(normal, fc, flash) : normal);
        c.drawRect(paddleX - paddleWidth()/2f, paddleY(), paddleX + paddleWidth()/2f, paddleY()+PADDLE_HEIGHT, paint);
        paint.setColor(Color.WHITE); paint.setAlpha(255);
        for (BallState b : balls) if (b.active) c.drawRect(b.x, b.y, b.x + BALL_SIZE, b.y + BALL_SIZE, paint);
        if (state == SERVING) drawText(c, "Tap to serve", LOGICAL_WIDTH/2f, height()/2f + 20, 18);
    }

    private void drawRightText(Canvas c, String text, float x, float top, float size) {
        paint.setTextSize(size); paint.setTextAlign(Paint.Align.RIGHT);
        Paint.FontMetrics fm = paint.getFontMetrics();
        c.drawText(text, x, top + (size - (fm.bottom - fm.top))/2f - fm.top, paint);
        paint.setTextAlign(Paint.Align.CENTER);
    }
    private String effectText() {
        StringBuilder out = new StringBuilder();
        if (longPaddleTicks > 0) out.append("P ").append((longPaddleTicks + 59)/60);
        if (shortPaddleTicks > 0) { if (out.length()>0) out.append("  "); out.append("R ").append((shortPaddleTicks+59)/60); }
        if (slowTicks > 0) { if (out.length()>0) out.append("  "); out.append("S ").append((slowTicks+59)/60); }
        return out.toString();
    }
    private void drawCapsule(Canvas c, int type, float x, float y) {
        paint.setColor(POWER_COLORS[type]); c.drawRect(x, y, x + CAPSULE_WIDTH, y + CAPSULE_HEIGHT, paint);
        paint.setColor(Color.WHITE); drawText(c, POWER_LETTERS[type], x + CAPSULE_WIDTH/2f, y, 11);
    }
    private static int blend(int a, int b, float ratio) {
        float r = Math.max(0, Math.min(1, ratio));
        return Color.rgb((int)(Color.red(a)*(1-r)+Color.red(b)*r), (int)(Color.green(a)*(1-r)+Color.green(b)*r), (int)(Color.blue(a)*(1-r)+Color.blue(b)*r));
    }

    public boolean handleBackPressed() {
        if (state == PAUSED) { state = pausedState; timerRunning = state == PLAYING; }
        else if (state == SERVING || state == PLAYING || state == LEVEL_COMPLETE) {
            pausedState = state; timerRunning = false; state = PAUSED;
        } else if (state == HOW_TO_PLAY || state == LOST) state = TITLE;
        else return false;
        invalidate(); return true;
    }
}
