// 템포루틴 Android — 설정 (iOS SettingsView 이식, P0 축소: 테마·언어·알림·건강·동기화·구입 내역·캐시 없음)
// 구획 순서는 iOS 정보 구조를 따른다: 기록할 것 → 캘린더 → 안내 → 리듬 설문 → 데이터 → 파괴적 액션.
// 파일 입출력은 SAF(CreateDocument/OpenDocument) — 앱이 저장 위치를 고르지 않는다.

package app.temporoutine.android.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.R
import app.temporoutine.android.TempoApp
import app.temporoutine.android.selfreport.SelfReportFlow
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.theme.milkGlass
import app.temporoutine.android.today.InfoBadge
import app.temporoutine.core.ExportEnvelopeV1
import app.temporoutine.core.TrackedSignals
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.delay

private const val PRIVACY_URL = "https://yewon419.github.io/temporoutine-site/privacy.html"
private const val UNDO_SECONDS = 8L

@Composable
fun SettingsRoute(app: TempoApp, hazeState: HazeState, bottomPadding: Dp) {
    val vm: SettingsViewModel = viewModel { SettingsViewModel(app) }
    val state by vm.state.collectAsState()
    val event by vm.events.collectAsState()
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current

    var pendingExport by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var undo by remember { mutableStateOf<ExportEnvelopeV1?>(null) }
    var showWipeConfirm by remember { mutableStateOf(false) }
    var showSurvey by remember { mutableStateOf(false) }

    val saver = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        val text = pendingExport
        pendingExport = null
        if (uri == null || text == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } ?: error("no stream")
        }.isSuccess
        notice = context.getString(if (ok) R.string.settings_export_done else R.string.settings_export_failed)
    }
    val opener = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val text = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }
        }.getOrNull()
        if (text == null) notice = context.getString(R.string.settings_import_corrupt) else vm.importJson(text)
    }

    // VM 이벤트 → 문구. 되돌리기 봉투는 8초만 들고 있는다.
    LaunchedEffect(event) {
        when (val e = event) {
            null -> return@LaunchedEffect
            is SettingsEvent.Imported ->
                notice = if (e.added > 0) context.getString(R.string.settings_import_done, e.added)
                else context.getString(R.string.settings_import_empty)
            SettingsEvent.ImportNewerVersion -> notice = context.getString(R.string.settings_import_newer)
            SettingsEvent.ImportCorrupt -> notice = context.getString(R.string.settings_import_corrupt)
            SettingsEvent.ExportFailed -> notice = context.getString(R.string.settings_export_failed)
            is SettingsEvent.Wiped -> undo = e.undo
            SettingsEvent.UndoDone -> undo = null
        }
        vm.consumeEvent()
    }
    LaunchedEffect(undo) {
        if (undo == null) return@LaunchedEffect
        delay(UNDO_SECONDS * 1000)
        undo = null
    }

    SettingsScreen(
        state = state, hazeState = hazeState, bottomPadding = bottomPadding,
        onSignals = vm::setSignals,
        onHidePeriodEntry = vm::setHidePeriodEntry,
        onRevisitOnboarding = vm::beginOnboardingRevisit,
        onSurvey = { showSurvey = true },
        onExport = { vm.exportJson { text -> pendingExport = text; saver.launch(vm.exportFileName()) } },
        onImport = { opener.launch(arrayOf("application/json")) },
        onPrivacy = { uriHandler.openUri(PRIVACY_URL) },
        onWipe = { showWipeConfirm = true },
        undoVisible = undo != null,
        onUndo = { undo?.let(vm::undoWipe) },
    )

    if (showWipeConfirm) {
        val ink = Ink
        AlertDialog(
            onDismissRequest = { showWipeConfirm = false },
            title = { Text(stringResource(R.string.settings_wipe)) },
            text = { Text(stringResource(R.string.settings_wipe_confirm_body)) },
            confirmButton = {
                TextButton(onClick = { showWipeConfirm = false; vm.wipeAll() }) {
                    Text(stringResource(R.string.settings_wipe_confirm), color = ink.danger)
                }
            },
            dismissButton = { TextButton(onClick = { showWipeConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (notice != null) {
        AlertDialog(
            onDismissRequest = { notice = null },
            confirmButton = { TextButton(onClick = { notice = null }) { Text(stringResource(R.string.ok)) } },
            text = { Text(notice.orEmpty()) },
        )
    }
    if (showSurvey) {
        SelfReportFlow(
            previousAnswers = state.lastAnswers,
            onSubmit = vm::submitSelfReport,
            onDismiss = { showSurvey = false },
        )
    }
}

@Composable
fun SettingsScreen(
    state: SettingsUiState, hazeState: HazeState, bottomPadding: Dp,
    onSignals: (TrackedSignals) -> Unit, onHidePeriodEntry: (Boolean) -> Unit,
    onRevisitOnboarding: () -> Unit, onSurvey: () -> Unit, onExport: () -> Unit, onImport: () -> Unit,
    onPrivacy: () -> Unit, onWipe: () -> Unit, undoVisible: Boolean, onUndo: () -> Unit,
) {
    val ink = Ink
    Box(Modifier.fillMaxSize().background(ink.paper)) {
        if (!state.loaded) return@Box
        SeasonLight(phase = null, modifier = Modifier.fillMaxSize().hazeSource(hazeState))
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(20.dp)
                .padding(bottom = bottomPadding),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(stringResource(R.string.tab_settings), style = Fonts.almanac(28), color = ink.text)

            // ── 기록할 것 ──
            SettingsSection(stringResource(R.string.ob_signals_eyebrow), hazeState) {
                val t = state.signals
                SignalToggleRow(stringResource(R.string.ob_sig_sleep), stringResource(R.string.ob_sig_sleep_info), t.sleep) {
                    onSignals(t.copy(sleep = it))
                }
                SignalToggleRow(stringResource(R.string.ob_sig_appetite), stringResource(R.string.ob_sig_appetite_info), t.appetite) {
                    onSignals(t.copy(appetite = it))
                }
                SignalToggleRow(stringResource(R.string.ob_sig_note), stringResource(R.string.ob_sig_note_info), t.note) {
                    onSignals(t.copy(note = it))
                }
            }
            Caption(stringResource(R.string.settings_signals_foot))

            // ── 캘린더 ──
            SettingsSection(stringResource(R.string.tab_calendar), hazeState) {
                ToggleRow(stringResource(R.string.settings_hide_period_entry), state.hidePeriodEntry, onHidePeriodEntry)
            }
            if (state.hidePeriodEntry) Caption(stringResource(R.string.settings_hide_period_entry_foot))

            // ── 안내·설문 ──
            SettingsSection(stringResource(R.string.settings_guide), hazeState) {
                ActionRow(stringResource(R.string.settings_onboarding_revisit), onRevisitOnboarding)
                ActionRow(
                    stringResource(if (state.hasSelfReport) R.string.settings_survey_again else R.string.settings_survey),
                    onSurvey,
                )
            }
            if (state.hasSelfReport) Caption(stringResource(R.string.settings_survey_foot))

            // ── 데이터 ──
            SettingsSection(stringResource(R.string.settings_data), hazeState) {
                ActionRow(stringResource(R.string.settings_export), onExport)
                ActionRow(stringResource(R.string.settings_import), onImport)
                ActionRow(stringResource(R.string.settings_privacy), onPrivacy)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Caption(stringResource(R.string.settings_data_foot_counts, state.periodDayCount, state.checkInCount))
                Caption(stringResource(R.string.settings_data_foot_transfer))
            }

            // ── 파괴적 액션 ──
            SettingsSection(null, hazeState) {
                ActionRow(stringResource(R.string.settings_wipe), onWipe, color = ink.danger)
            }
        }
        if (undoVisible) {
            Row(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = bottomPadding + 16.dp)
                    .background(ink.text, CircleShape)
                    .padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(stringResource(R.string.settings_wipe_done), style = Fonts.system(13), color = ink.paper)
                Text(
                    stringResource(R.string.settings_undo), style = Fonts.system(13, FontWeight.Bold), color = ink.paper,
                    modifier = Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onUndo),
                )
            }
        }
    }
}

@Composable
private fun SettingsSection(title: String?, hazeState: HazeState, content: @Composable () -> Unit) {
    val ink = Ink
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) {
            Text(title, style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.5f), modifier = Modifier.padding(start = 4.dp))
        }
        Column(Modifier.fillMaxWidth().milkGlass(hazeState).padding(horizontal = 16.dp, vertical = 4.dp)) { content() }
    }
}

@Composable
private fun Caption(text: String) {
    Text(text, style = Fonts.system(12), color = Ink.text.copy(alpha = 0.5f), modifier = Modifier.padding(horizontal = 4.dp))
}

@Composable
private fun SignalToggleRow(name: String, info: String, value: Boolean, onChange: (Boolean) -> Unit) {
    val ink = Ink
    // 행 전체가 스위치를 뒤집는다(iOS Toggle 행과 같은 타깃) — ⓘ만 예외로 제 다이얼로그를 연다
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onChange(!value) }
            .padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        InfoBadge(title = name, message = info)
        Text(name, style = Fonts.system(15), color = ink.text)
        Spacer(Modifier.weight(1f))
        TempoSwitch(value, onChange)
    }
}

@Composable
private fun ToggleRow(name: String, value: Boolean, onChange: (Boolean) -> Unit) {
    val ink = Ink
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onChange(!value) }
            .padding(vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, style = Fonts.system(15), color = ink.text, modifier = Modifier.weight(1f))
        TempoSwitch(value, onChange)
    }
}

@Composable
private fun TempoSwitch(value: Boolean, onChange: (Boolean) -> Unit) {
    val ink = Ink
    Switch(
        checked = value, onCheckedChange = onChange,
        colors = SwitchDefaults.colors(
            checkedTrackColor = ink.text, checkedThumbColor = ink.paper,
            uncheckedTrackColor = ink.text.copy(alpha = 0.12f), uncheckedThumbColor = ink.text.copy(alpha = 0.6f),
            uncheckedBorderColor = Color.Transparent,
        ),
    )
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit, color: Color = Ink.text) {
    Text(
        title, style = Fonts.system(15), color = color,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(vertical = 14.dp),
    )
}
