/* static/admin/js/custom_schedule_filter.js */

(function($) {
    $(document).ready(function() {
        console.log("🚀 스케줄 필터 스크립트 시작됨!");

        // URL에서 현재 수정 중인 학생의 User ID 추출 (없으면 null)
        // 예: .../studentuser/123/change/... -> 123 추출
        const urlMatch = window.location.pathname.match(/studentuser\/(\d+)\/change/);
        const currentStudentId = urlMatch ? urlMatch[1] : null;

        console.log("현재 학생 User ID:", currentStudentId);

        // 감시할 대상 정의 (ID가 조금 달라도 찾을 수 있게 '끝자리'로 매칭)
        const mappings = [
            { role: 'syntax',  teacherSuffix: '-syntax_teacher',  classSuffix: '-syntax_class' },
            { role: 'reading', teacherSuffix: '-reading_teacher', classSuffix: '-reading_class' },
            { role: 'extra',   teacherSuffix: '-extra_class_teacher', classSuffix: '-extra_class' }
        ];

        function checkAndDisable(teacherSelect, classSelect, role) {
            const teacherId = $(teacherSelect).val();
            const $timeSelect = $(classSelect);

            // 선생님 선택 해제 시 -> 초기화
            if (!teacherId) {
                $timeSelect.find('option').prop('disabled', false).css('color', '').each(function() {
                    $(this).text($(this).text().replace(' ⛔(마감)', ''));
                });
                return;
            }

            const currentVal = $timeSelect.val(); // 현재 선택된 값 유지

            // API 요청
            $.ajax({
                url: '/academy/api/admin/teacher-schedule/',
                data: {
                    'teacher_id': teacherId,
                    'subject': role,
                    'current_student_id': currentStudentId // 본인 제외용
                },
                success: function(response) {
                    const occupiedIds = response.occupied_ids;
                    console.log(`[${role}] 마감된 시간 ID 목록:`, occupiedIds);

                    $timeSelect.find('option').each(function() {
                        const optVal = parseInt($(this).val());
                        
                        // "마감 목록에 있고" AND "내가 지금 선택한 게 아니라면" -> 비활성화
                        const isOccupied = occupiedIds.includes(optVal);
                        const isSelected = (optVal == currentVal);

                        // 텍스트에서 '마감' 꼬리표 뗐다가 다시 붙이기 (중복 방지)
                        let text = $(this).text().replace(' ⛔(마감)', '');

                        if (isOccupied && !isSelected) {
                            $(this).prop('disabled', true);     // 선택 불가
                            $(this).css('color', '#cccccc');    // 회색 처리
                            $(this).css('font-style', 'italic');// 기울임
                            $(this).text(text + ' ⛔(마감)');
                        } else {
                            $(this).prop('disabled', false);    // 선택 가능
                            $(this).css('color', '');           // 색상 복구
                            $(this).css('font-style', '');
                            $(this).text(text);
                        }
                    });
                },
                error: function(err) {
                    console.error("API 호출 에러:", err);
                }
            });
        }

        // 모든 select 요소를 뒤져서 이벤트 연결
        mappings.forEach(function(map) {
            // ID가 "~-syntax_teacher" 로 끝나는 모든 select 태그 찾기
            const $teacherSelects = $(`select[id$="${map.teacherSuffix}"]`);
            
            $teacherSelects.each(function() {
                const teacherId = $(this).attr('id'); // 예: id_studentprofile-0-syntax_teacher
                // 짝꿍 시간표 ID 찾기 (teacher -> class 로 치환)
                const classId = teacherId.replace(map.teacherSuffix, map.classSuffix);
                const $classSelect = $(document.getElementById(classId));

                if ($classSelect.length > 0) {
                    console.log(`✅ 연결 성공: ${teacherId} <-> ${classId}`);
                    
                    // 1. 선생님 바꾸면 실행
                    $(this).on('change', function() {
                        checkAndDisable(this, $classSelect, map.role);
                    });

                    // 2. 페이지 로딩 시 실행 (이미 선택된 선생님이 있을 경우)
                    checkAndDisable(this, $classSelect, map.role);
                } else {
                    console.warn(`짝꿍 시간표를 못 찾음: ${classId}`);
                }
            });
        });
    });
})(django.jQuery);