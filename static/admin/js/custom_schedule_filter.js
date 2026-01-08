/* static/admin/js/custom_schedule_filter.js */

(function($) {
    $(document).ready(function() {
        // URL에서 현재 학생 ID 추출 (자신 제외용)
        const urlMatch = window.location.pathname.match(/studentuser\/(\d+)\/change/);
        const currentStudentId = urlMatch ? urlMatch[1] : null;

        const mappings = [
            { role: 'syntax',  teacherIdSuffix: '-syntax_teacher',  classIdSuffix: '-syntax_class' },
            { role: 'reading', teacherIdSuffix: '-reading_teacher', classIdSuffix: '-reading_class' },
            { role: 'extra',   teacherIdSuffix: '-extra_class_teacher', classIdSuffix: '-extra_class' }
        ];

        function checkAndDisable($teacherSelect, $classSelect, role) {
            const teacherId = $teacherSelect.val();
            
            // 선생님이 없으면 중단
            if (!teacherId) {
                // 선택 불가는 풀되, 마감 텍스트는 지워줌
                $classSelect.find('option').prop('disabled', false).each(function() {
                     $(this).text($(this).text().replace(' ⛔(마감)', ''));
                });
                return;
            }

            const currentVal = $classSelect.val(); 

            $.ajax({
                url: '/academy/api/admin/teacher-schedule/',
                data: {
                    'teacher_id': teacherId,
                    'subject': role,
                    'current_student_id': currentStudentId
                },
                success: function(response) {
                    const occupiedIds = response.occupied_ids;

                    $classSelect.find('option').each(function() {
                        const optVal = parseInt($(this).val());
                        if (isNaN(optVal)) return;

                        // 현재 텍스트에서 (마감) 글자 제거 (중복 방지)
                        let text = $(this).text().replace(' ⛔(마감)', '');

                        const isOccupied = occupiedIds.includes(optVal);
                        const isSelected = (optVal == currentVal);

                        if (isOccupied && !isSelected) {
                            $(this).prop('disabled', true);
                            $(this).css({ 'color': '#cccccc', 'font-style': 'italic' });
                            $(this).text(text + ' ⛔(마감)');
                        } else {
                            $(this).prop('disabled', false);
                            $(this).css({ 'color': '', 'font-style': '' });
                            $(this).text(text);
                        }
                    });
                }
            });
        }

        // 페이지 내 모든 매핑 대상 찾기
        mappings.forEach(function(map) {
            // ID가 ...-syntax_teacher 로 끝나는 모든 select 찾기
            const $teacherSelects = $('select[id$="' + map.teacherIdSuffix + '"]');

            $teacherSelects.each(function() {
                const $teacherSelect = $(this);
                const teacherSelectId = $teacherSelect.attr('id');
                
                // 짝꿍 시간표 ID 찾기
                const classSelectId = teacherSelectId.replace(map.teacherIdSuffix, map.classIdSuffix);
                const $classSelect = $('#' + classSelectId);

                if ($classSelect.length > 0) {
                    // 1. 선생님 변경 시 -> 검사
                    $teacherSelect.on('change', function() {
                        checkAndDisable($teacherSelect, $classSelect, map.role);
                    });

                    // 2. ✅ [중요] 시간표 목록이 갱신되었다는 신호를 받으면 -> 재검사
                    $classSelect.on('options_refreshed', function() {
                        checkAndDisable($teacherSelect, $classSelect, map.role);
                    });

                    // 3. 초기 로드 시 실행
                    // (단, class_time_filter가 로드되면서 곧바로 내용을 바꿀 수 있으므로
                    //  options_refreshed 이벤트에 맡기는 것이 더 안전하지만, 혹시 모르니 실행)
                    if ($teacherSelect.val()) {
                        checkAndDisable($teacherSelect, $classSelect, map.role);
                    }
                }
            });
        });
    });
})(django.jQuery);