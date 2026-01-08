/* static/admin/js/class_time_filter.js */

(function($) {
    const FIELD_RULES = [
        { suffix: 'syntax_class', teacherSuffix: 'syntax_teacher', keyword: '구문', role: 'syntax', typeDependency: false },
        { suffix: 'reading_class', teacherSuffix: 'reading_teacher', keyword: '독해', role: 'reading', typeDependency: false },
        { suffix: 'extra_class', teacherSuffix: 'extra_class_teacher', keyword: '', role: 'extra', typeDependency: true }
    ];

    $(document).ready(function() {
        console.log("🚀 [System V5] 요일필터 복구 + 선생님 연동 로직 시작");

        // 1. 로드 시 모든 행 초기화
        $('select[name$="-branch"]').each(function() { initializeRow($(this)); });

        // 2. 행 추가 시 초기화
        $(document).on('formset:added', function(e, $row) {
            $row.find('select[name$="-branch"]').each(function() { initializeRow($(this)); });
        });
    });

    function initializeRow($branchSelect) {
        const branchId = $branchSelect.attr('id');
        if (!branchId) return;
        const prefix = branchId.substring(0, branchId.lastIndexOf('-'));

        FIELD_RULES.forEach(function(rule) {
            const $timeSelect = $('#' + prefix + '-' + rule.suffix);
            const $teacherSelect = $('#' + prefix + '-' + rule.teacherSuffix);

            if ($timeSelect.length) {
                // (1) 요일 필터 UI 생성 (가장 먼저 실행)
                const $dayFilter = createDayFilter($timeSelect);

                const targetObj = { 
                    $el: $timeSelect, 
                    $teacherEl: $teacherSelect, 
                    $dayFilter: $dayFilter,
                    rule: rule, 
                    prefix: prefix 
                };

                // (2) 추가수업 타입 필터 찾기
                if (rule.typeDependency) {
                    targetObj.$typeEl = $('#' + prefix + '-extra_class_type');
                }

                // (3) 이벤트 리스너 등록
                
                // A. 지점 변경 -> 데이터 새로 가져옴
                $branchSelect.on('change', () => fetchDataAndRender(targetObj, $branchSelect.val()));

                // B. 선생님 변경 -> 데이터 새로 가져옴 (마감 정보 갱신)
                if ($teacherSelect.length) {
                    $teacherSelect.on('change', () => fetchDataAndRender(targetObj, $branchSelect.val()));
                }

                // C. 요일 변경 -> [중요] 서버 요청 없이 화면만 다시 그림 (Local Filtering)
                $dayFilter.on('change', () => localRender(targetObj));

                // D. 추가수업 타입 변경 -> 화면 다시 그림
                if (targetObj.$typeEl) {
                    targetObj.$typeEl.on('change', () => localRender(targetObj));
                }

                // (4) 초기 로드 시 실행 (수정 모드 대응)
                if ($branchSelect.val()) {
                    fetchDataAndRender(targetObj, $branchSelect.val());
                }
            }
        });
    }

    // [UI] 요일 필터 박스 생성 함수
    function createDayFilter($select) {
        if ($select.prev('.day-filter-box').length > 0) {
            return $select.prev('.day-filter-box');
        }
        
        const $filter = $('<select class="day-filter-box" style="margin-right:5px; width:80px; padding: 5px;">')
            .append('<option value="">📅 요일</option>')
            .append('<option value="월요일">월요일</option>')
            .append('<option value="화요일">화요일</option>')
            .append('<option value="수요일">수요일</option>')
            .append('<option value="목요일">목요일</option>')
            .append('<option value="금요일">금요일</option>')
            .append('<option value="토요일">토요일</option>')
            .append('<option value="일요일">일요일</option>');
        
        $select.before($filter);
        return $filter;
    }

    // [Step 1] 서버에서 데이터 가져오기 (지점 + 선생님 정보 포함)
    function fetchDataAndRender(target, branchId) {
        if (!branchId) {
            target.$el.html('<option value="">---------</option>');
            return;
        }

        const teacherId = target.$teacherEl ? target.$teacherEl.val() : '';
        // 현재 URL에서 학생 ID 추출 (자기 자신 중복 제외용)
        const currentStudentId = (window.location.pathname.match(/studentuser\/(\d+)\/change/) || [])[1] || '';

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: {
                'branch_id': branchId,
                'teacher_id': teacherId,
                'role': target.rule.role,
                'student_id': currentStudentId
            },
            success: function(data) {
                // [핵심] 받아온 데이터를 DOM 요소에 저장해둠 (캐싱)
                // 요일 필터를 바꿀 때마다 서버에 요청하지 않고 이 데이터를 씀.
                target.$el.data('cached-times', data);
                
                // 화면 그리기
                localRender(target);
            },
            error: function(err) {
                console.error("시간표 로딩 실패", err);
            }
        });
    }

    // [Step 2] 저장된 데이터를 기반으로 화면 그리기 (요일 필터 적용)
    function localRender(target) {
        const data = target.$el.data('cached-times');
        if (!data) return; // 데이터가 없으면 중단

        const currentVal = target.$el.val(); // 현재 선택된 값 유지용
        const selectedDay = target.$dayFilter.val(); // 선택된 요일

        // 1. 키워드 결정 (구문/독해)
        let keyword = target.rule.keyword;
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val();
            if (typeVal === 'SYNTAX') keyword = '구문';
            else if (typeVal === 'READING') keyword = '독해';
        }

        // 2. HTML 생성
        let html = '<option value="">---------</option>';

        data.forEach(function(item) {
            // (A) 키워드 필터링
            if (keyword && item.raw_name.indexOf(keyword) === -1) return;

            // (B) 요일 필터링 (선택된 요일이 있고, 매칭되지 않으면 스킵)
            if (selectedDay && item.name.indexOf(selectedDay) === -1) return;

            // (C) 마감(Disabled) 처리
            // 내 수업(현재 선택된 값)이면 마감이어도 활성화, 남의 수업이면 비활성화
            const isSelected = (String(item.id) === String(currentVal));
            const disabledAttr = (item.disabled && !isSelected) ? 'disabled' : '';
            
            // 스타일링: 마감된 건 회색+기울임
            const styleAttr = (item.disabled && !isSelected) ? 'style="color:#ccc; font-style:italic; background-color:#f9f9f9;"' : '';

            html += `<option value="${item.id}" ${disabledAttr} ${styleAttr}>${item.name}</option>`;
        });

        // 3. DOM 교체
        target.$el.html(html);

        // 4. 값 복구
        if (currentVal) target.$el.val(currentVal);
    }

})(django.jQuery);